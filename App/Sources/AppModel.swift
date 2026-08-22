import Foundation
import MediaPlayer
import SwiftUI

/// App-level glue: tab routing, the active engine, note capture with its
/// pause/resume policy, and now-playing updates.
@MainActor
final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case library, audiobook, reader, scan
    }

    let store: ListnrStore
    let engine: any PlayerEngine
    @Published var tab: Tab = .library

    @Published private(set) var currentBookID: UUID?
    /// Set while the note sheet is open; drives the auto-pause policy.
    @Published var noteCaptureActive = false

    private var resumeAfterNote = false

    /// UI tests and previews can force the deterministic engine.
    static func makeEngine() -> any PlayerEngine {
        if ProcessInfo.processInfo.arguments.contains("-mockengine") {
            return MockEngine()
        }
        return AudioPlayerEngine()
    }

    init(store: ListnrStore, engine: (any PlayerEngine)? = nil) {
        self.store = store
        self.engine = engine ?? Self.makeEngine()

        if let last = store.lastListenedID, store.books.first(where: { $0.id == last })?.hasAudio == true {
            currentBookID = last
        } else {
            currentBookID = store.books.first(where: { $0.hasAudio })?.id
        }
        loadCurrentBook(into: self.engine)

        // deep-launch support: `-tab audiobook|reader|scan|library`
        let argv = ProcessInfo.processInfo.arguments
        if let i = argv.firstIndex(of: "-tab"), i + 1 < argv.count,
           let t = Tab(rawValue: argv[i + 1]) {
            tab = t
        }

        self.engine.onChange = { [weak self] in self?.engineChanged() }
    }

    var currentBook: Book? {
        guard let id = currentBookID else { return nil }
        return store.books.first { $0.id == id }
    }

    // MARK: opening books

    func openBook(_ id: UUID) {
        guard let book = store.books.first(where: { $0.id == id }) else { return }
        if book.isPaired || book.hasAudio {
            openInPlayer(book)
        } else {
            store.markRead(bookID: id)
            tab = .reader
        }
    }

    func openResumeListening() {
        let id = store.lastListenedID ?? store.books.first(where: { $0.hasAudio })?.id
        guard let id, let book = store.books.first(where: { $0.id == id }), book.hasAudio else { return }
        openInPlayer(book)
    }

    func openResumeReading() {
        guard let id = store.lastReadID else {
            tab = .reader
            return
        }
        tab = .reader   // reader is under construction; still records intent
    }

    private func openInPlayer(_ book: Book) {
        if book.id != currentBookID {
            persistPosition()
            currentBookID = book.id
            loadCurrentBook(into: engine)
        }
        store.markListened(bookID: book.id)
        tab = .audiobook
    }

    private func loadCurrentBook(into target: (any PlayerEngine)?) {
        guard let book = currentBook, book.hasAudio, let url = book.audioURL else { return }
        do {
            try target?.load(url: url, startPosition: book.position, speed: book.speed)
            updateNowPlaying(book: book)
        } catch {
            NSLog("Listnr: failed to load \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: engine state -> store

    func engineChanged() {
        // the engine is not itself observed by views; forward its changes
        objectWillChange.send()
        guard let book = currentBook else { return }
        updateNowPlaying(book: book)
        if !engine.isPlaying {
            persistPosition()
        }
    }

    func persistPosition() {
        guard let id = currentBookID else { return }
        store.updatePosition(bookID: id, position: engine.position, speed: engine.speed)
    }

    private func updateNowPlaying(book: Book) {
        guard engine is AudioPlayerEngine else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = NowPlaying.build(
            title: book.title, author: book.author,
            chapter: book.currentChapter?.title,
            position: engine.position, duration: engine.duration, rate: engine.isPlaying ? engine.speed : 0)
    }

    // MARK: transport passthroughs used by views

    func togglePlay() {
        engine.togglePlay()
        if let book = currentBook {
            updateNowPlaying(book: book)
        }
    }

    func setSpeed(_ speed: Double) {
        engine.setSpeed(speed)
        persistPosition()
    }

    func selectChapter(_ chapter: Chapter) {
        engine.seek(to: chapter.start + 0.01)
        persistPosition()
    }

    func previousChapter() {
        guard let book = currentBook else { return }
        if let target = ChapterMath.previousChapterStart(
            position: engine.position, duration: book.duration, count: book.chapterCount) {
            engine.seek(to: target)
        }
    }

    func nextChapter() {
        guard let book = currentBook else { return }
        if let target = ChapterMath.nextChapterStart(
            position: engine.position, duration: book.duration, count: book.chapterCount) {
            engine.seek(to: min(target, max(0, engine.duration - 0.05)))
        }
    }

    func armSleep(minutes: Int?) {
        engine.armSleepTimer(minutes: minutes)
    }

    // MARK: notes — capture pauses playback; saving or cancelling resumes

    func beginNoteCapture() {
        noteCaptureActive = true
        resumeAfterNote = engine.isPlaying
        if engine.isPlaying { engine.pause() }
    }

    func saveNote(text: String) {
        defer {
            noteCaptureActive = false
            if resumeAfterNote { engine.play() }
            resumeAfterNote = false
        }
        guard let id = currentBookID, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        _ = store.addNote(bookID: id, text: text, timestamp: engine.position)
    }

    func cancelNoteCapture() {
        noteCaptureActive = false
        if resumeAfterNote { engine.play() }
        resumeAfterNote = false
    }

    /// Jump straight to a timestamp from the notes list.
    func selectChapterTimestamp(_ time: TimeInterval) {
        engine.seek(to: max(0, min(time, max(0, engine.duration - 0.05))))
        persistPosition()
    }

    var notesForCurrentBook: [Note] {
        guard let id = currentBookID else { return [] }
        return store.notes[id] ?? []
    }
}
