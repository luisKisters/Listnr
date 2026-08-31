import BackgroundTasks
import Foundation
import MediaPlayer
import SwiftUI
import UIKit

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
    /// A visible reason the current book is not playable — an iCloud file that
    /// is still downloading, or a folder whose scope was refused. Never silent.
    @Published private(set) var playbackNotice: String?
    /// True while a folder scan runs; the library shows it as a quiet line.
    @Published private(set) var isScanning = false
    /// Drives the library's import sheet. On the model, not on the view, so a
    /// launch argument can open it for the evidence screenshots.
    @Published var importSheetActive = false

    private var resumeAfterNote = false
    /// Set by `-sheet note`; the capture starts after the engine is wired.
    private var openNoteOnLaunch = false

    /// The security scope of the folder the loaded book lives in. Held for the
    /// life of the loaded book (plan risk 5), never only for the scan.
    private var folderAccess: FolderSource.Access?
    /// Lock-screen artwork of the loaded book, rendered once and kept in
    /// memory — never written to disk (plan amendment 2).
    private var artwork: UIImage?
    private var artworkBookID: UUID?

    let indexer = LibraryIndexer()
    /// `nonisolated(unsafe)` so `deinit` can hand it back to the notification
    /// centre: it is written once in `init` and read once in `deinit`.
    private nonisolated(unsafe) var foregroundObserver: (any NSObjectProtocol)?
    private var lastRescanAt: Date?
    private var rescanTask: Task<Void, Never>?
    /// Debounce window for the foreground rescan.
    private let rescanInterval: TimeInterval = 5

    /// UI tests and previews can force the deterministic engine.
    static func makeEngine() -> any PlayerEngine {
        if ProcessInfo.processInfo.arguments.contains("-mockengine") {
            return MockEngine()
        }
        return AudioPlayerEngine()
    }

    init(
        store: ListnrStore, engine: (any PlayerEngine)? = nil,
        modelCache: AsrModelCache = .onDisk()
    ) {
        self.store = store
        self.engine = engine ?? Self.makeEngine()
        self.modelCache = modelCache
        self.modelDownload = modelCache.isDownloaded() ? .ready : .missing

        if let last = store.lastListenedID, store.books.first(where: { $0.id == last })?.hasAudio == true {
            currentBookID = last
        } else {
            currentBookID = store.books.first(where: { $0.hasAudio })?.id
        }
        loadCurrentBook(into: self.engine)
        #if DEBUG
        if ScanFixture.isActive, let id = currentBookID {
            ScanFixture.install(bookID: id)
        }
        // Screenshot states for scripts/evidence.sh — never set by the app.
        if ProcessInfo.processInfo.arguments.contains("-modeldownloading") {
            modelDownload = .downloading(0.42)
        }
        if ProcessInfo.processInfo.arguments.contains("-preparing") {
            preparationProgress = 0.42
        }
        #endif

        // deep-launch support: `-tab audiobook|reader|scan|library`
        let argv = ProcessInfo.processInfo.arguments
        if let i = argv.firstIndex(of: "-tab"), i + 1 < argv.count,
           let t = Tab(rawValue: argv[i + 1]) {
            tab = t
        }
        // deep-launch support: `-sheet import|note` for the evidence shots.
        // The note sheet goes through the real capture path, pause policy and
        // all — a shortcut would photograph something the app never shows.
        if let i = argv.firstIndex(of: "-sheet"), i + 1 < argv.count {
            switch argv[i + 1] {
            case "import": importSheetActive = true
            case "note": openNoteOnLaunch = true
            default: break
            }
        }

        self.engine.onChange = { [weak self] in self?.engineChanged() }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rescanSources()
                self?.refreshModelState()
                self?.resumeCheckpointedPreparation()
            }
        }
        rescanSources()
        if openNoteOnLaunch {
            openNoteOnLaunch = false
            beginNoteCapture()
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    var currentBook: Book? {
        guard let id = currentBookID else { return nil }
        return store.books.first { $0.id == id }
    }

    // MARK: opening books

    func openBook(_ id: UUID) {
        guard let book = store.books.first(where: { $0.id == id }) else { return }
        // A missing file has nothing to open — anything else is a dead control.
        guard !book.isMissing else { return }
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

    /// Loads a book and holds everything that book needs for its whole life:
    /// the folder's security scope and its lock-screen artwork.
    private func loadCurrentBook(into target: (any PlayerEngine)?) {
        releaseFolderAccess()
        playbackNotice = nil
        artwork = nil
        artworkBookID = nil
        guard let book = currentBook, book.hasAudio, !book.isMissing,
              let url = book.audioURL else { return }

        if let folderID = book.sourceFolderID, let folder = store.folder(id: folderID) {
            do {
                let access = try folder.beginAccess()
                if let fresh = access.refreshedBookmark {
                    store.updateBookmark(folderID: folderID, bookmark: fresh)
                }
                folderAccess = access
            } catch {
                playbackNotice = "This folder needs to be picked again."
                return
            }
        }

        // Plan risk 4: AVAudioPlayer wants the whole file locally.
        guard Self.ensureLocal(url) else {
            playbackNotice = "Downloading from iCloud — this book plays once the file is local."
            releaseFolderAccess()
            return
        }

        do {
            try target?.load(url: url, startPosition: book.position, speed: book.speed)
            updateNowPlaying(book: book)
        } catch {
            playbackNotice = "This file could not be opened."
            releaseFolderAccess()
            NSLog("Listnr: failed to load \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func releaseFolderAccess() {
        folderAccess?.end()
        folderAccess = nil
    }

    /// True when the file is on this device. An iCloud file that is not
    /// downloaded starts downloading and reports false — the caller shows it.
    nonisolated static func ensureLocal(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else { return true }
        if values.ubiquitousItemDownloadingStatus == .current { return true }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return false
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
            position: engine.position, duration: engine.duration,
            rate: engine.isPlaying ? engine.speed : 0,
            artwork: lockScreenArtwork(for: book))
    }

    /// The lock screen never shows a blank square: embedded artwork when the
    /// container had some, otherwise the typographic fallback rendered once per
    /// loaded book and kept in memory.
    private func lockScreenArtwork(for book: Book) -> UIImage? {
        if artworkBookID == book.id, let artwork { return artwork }
        let image = CoverImageStore.image(named: book.coverFileName)
            ?? Self.renderFallback(title: book.title, author: book.author)
        artwork = image
        artworkBookID = book.id
        return image
    }

    static func renderFallback(title: String, author: String, side: CGFloat = 600) -> UIImage? {
        let renderer = ImageRenderer(
            content: CoverView.Fallback(
                title: title, author: author, tone: Theme.coverTone(for: title))
                .frame(width: side, height: side))
        renderer.scale = 1
        return renderer.uiImage
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

    /// Falls back to a 15 s skip when the container declares no chapters.
    func previousChapter() {
        guard let book = currentBook else { return }
        guard let target = ChapterMath.previousStart(
            position: engine.position, in: book.chapters) else {
            engine.skipBack(15)
            return
        }
        engine.seek(to: target)
    }

    /// Falls back to a 30 s skip when the container declares no chapters.
    func nextChapter() {
        guard let book = currentBook else { return }
        guard let target = ChapterMath.nextStart(
            position: engine.position, in: book.chapters) else {
            if book.chapters.isEmpty { engine.skipForward(30) }
            return
        }
        engine.seek(to: min(target, max(0, engine.duration - 0.05)))
    }

    func armSleep(minutes: Int?) {
        engine.armSleepTimer(minutes: minutes)
    }

    // MARK: folder import and rescan

    /// One folder read, with everything the commit needs. Nothing is written
    /// until the user taps "Add to library".
    struct ImportPreview: Sendable {
        var folder: FolderSource
        var found: [IndexedBook]
        var refs: [StoredBookRef]
        var skipped: Int
        var isKnownFolder: Bool

        var reconciliation: Reconciliation {
            LibraryIndexer.reconcile(existing: refs, found: found)
        }

        var newCount: Int { reconciliation.added.count }
    }

    private struct FolderScan: Sendable {
        var result: ScanResult
        var refs: [StoredBookRef]
    }

    /// Walks a folder with its security scope held for the whole read, and
    /// reports each file name as it goes — there is no honest fraction to show
    /// before the enumeration ends (plan amendment 3).
    private func scan(
        folder: FolderSource, onFile: @MainActor @escaping (String) -> Void
    ) async throws -> FolderScan {
        let access = try folder.beginAccess()
        defer { access.end() }
        if let fresh = access.refreshedBookmark, store.folder(id: folder.id) != nil {
            store.updateBookmark(folderID: folder.id, bookmark: fresh)
        }
        let refs = store.bookRefs(folderID: folder.id)
        let known = store.knownIDs(folderID: folder.id)

        var result = ScanResult()
        for file in LibraryIndexer.audioFiles(in: access.url) {
            let path = LibraryIndexer.relativePath(of: file, in: access.url)
            onFile(file.lastPathComponent)
            do {
                result.books.append(
                    try await indexer.index(url: file, relativePath: path, id: known[path]))
            } catch {
                result.skipped += 1
            }
        }
        return FolderScan(result: result, refs: refs)
    }

    /// Reads a freshly picked folder. Writes nothing.
    func previewImport(
        url: URL, onFile: @MainActor @escaping (String) -> Void
    ) async throws -> ImportPreview {
        let known = store.folder(atPath: url)
        let target = try known ?? FolderSource.make(from: url)
        let scanned = try await scan(folder: target, onFile: onFile)
        return ImportPreview(
            folder: target, found: scanned.result.books, refs: scanned.refs,
            skipped: scanned.result.skipped, isKnownFolder: known != nil)
    }

    /// Commits a preview: the folder is remembered and the rows are written.
    @discardableResult
    func commitImport(_ preview: ImportPreview) -> (added: Int, updated: Int) {
        let folder = store.addFolder(preview.folder)
        let counts = store.apply(preview.reconciliation, folderID: folder.id)
        adoptFirstBookIfIdle()
        return counts
    }

    /// A folder whose bookmark died gets a new one from a fresh pick; the rows
    /// keep their notes and positions.
    func rePick(folderID: UUID, url: URL) throws {
        let bookmark = try FolderSource.makeBookmark(for: url)
        store.updateBookmark(folderID: folderID, bookmark: bookmark)
        rescanSources(force: true)
    }

    /// Runs on launch and on every foreground, at most once per 5 s. The scan
    /// itself happens on the indexer actor; only the result touches the store.
    func rescanSources(force: Bool = false) {
        guard !store.folders.isEmpty, rescanTask == nil else { return }
        if !force, let last = lastRescanAt, Date().timeIntervalSince(last) < rescanInterval {
            return
        }
        lastRescanAt = Date()
        isScanning = true
        rescanTask = Task { [weak self] in
            guard let self else { return }
            for folder in self.store.folders {
                guard let scanned = try? await self.scan(folder: folder, onFile: { _ in })
                else { continue }
                self.store.apply(
                    LibraryIndexer.reconcile(existing: scanned.refs, found: scanned.result.books),
                    folderID: folder.id)
            }
            self.isScanning = false
            self.rescanTask = nil
            self.adoptFirstBookIfIdle()
        }
    }

    /// After the first import the library has a book but nothing is loaded.
    private func adoptFirstBookIfIdle() {
        guard currentBookID == nil,
              let first = store.books.first(where: { $0.hasAudio && !$0.isMissing })
        else { return }
        currentBookID = first.id
        loadCurrentBook(into: engine)
    }

    // MARK: the speech model, downloaded once per install

    private let modelCache: AsrModelCache
    @Published private(set) var modelDownload: ModelDownload
    private var modelDownloadTask: Task<Void, Never>?
    /// The book the tap was about. It starts preparing the moment the model
    /// lands: the user already asked, and asking twice is a toll.
    private(set) var bookWaitingForModel: UUID?

    /// The download only runs in the foreground, so coming back is the moment
    /// the answer can have changed. A download in flight is not second-guessed,
    /// and a failure keeps its message until something is tried again.
    private func refreshModelState() {
        #if DEBUG
        // The evidence screenshots pin a fake state; the disk must not win.
        if ProcessInfo.processInfo.arguments.contains("-modeldownloading") { return }
        #endif
        guard modelDownloadTask == nil, modelDownload != .failed else { return }
        modelDownload = modelCache.isDownloaded() ? .ready : .missing
    }

    func downloadModel(then bookID: UUID?) {
        guard modelDownloadTask == nil, modelDownload != .ready else { return }
        bookWaitingForModel = bookID
        modelDownload = .downloading(0)
        // The download rides a continued-processing task when the system takes
        // one, so it keeps going when the phone locks. Refused (the simulator
        // always refuses) it runs in-app exactly as before.
        if !submitContinued(
            work: .download, title: "Downloading speech model",
            subtitle: "460 MB, once per phone") {
            modelDownloadTask = Task { [weak self] in await self?.runModelDownload() }
        }
    }

    /// Stop, named as what it is: there is no resume, so the next download
    /// starts at zero.
    func stopModelDownload() {
        modelDownloadTask?.cancel()
    }

    private func runModelDownload() async {
        // iOS gives roughly 30 s after the app leaves the foreground. This is
        // not a background transfer — that needs a background URLSession
        // FluidAudio does not expose — it only stops the task dying the instant
        // the phone locks.
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "Speech model")
        do {
            try await modelCache.download { [weak self] fraction in
                Task { @MainActor in self?.publishModelProgress(fraction) }
            }
            try Task.checkCancellation()
            modelDownload = .ready
            if let bookID = bookWaitingForModel { prepareForScanning(bookID: bookID) }
        } catch is CancellationError {
            modelDownload = .missing
        } catch {
            modelDownload = .failed
            NSLog("Listnr: the speech model could not be downloaded: \(error.localizedDescription)")
        }
        bookWaitingForModel = nil
        modelDownloadTask = nil
        UIApplication.shared.endBackgroundTask(assertion)
        finishBackgroundTask(success: modelDownload == .ready)
    }

    /// The bar never walks backwards — FluidAudio counts bytes over the whole
    /// repository and then restarts the count for the compile pass — and it
    /// never says 100 before the model is loaded.
    private func publishModelProgress(_ fraction: Double) {
        guard case .downloading(let shown) = modelDownload else { return }
        modelDownload = .downloading(max(shown, min(fraction, 0.99)))
        publishPillProgress(fraction)
    }

    // MARK: scan preparation

    private var transcriber: Transcriber?
    @Published private(set) var preparationProgress: Double?
    @Published private(set) var preparationNotice: String?
    private var preparationTask: Task<Void, Never>?
    private var preparationFolderAccess: FolderSource.Access?

    func prepareForScanning(bookID: UUID) {
        guard modelDownload == .ready,
              preparationTask == nil,
              let book = store.books.first(where: { $0.id == bookID }),
              let url = book.audioURL,
              !book.hasTranscript
        else { return }
        preparationNotice = nil
        preparationProgress = 0
        if !submitContinued(
            work: .prepare(bookID: bookID, url: url), title: "Preparing \(book.title)",
            subtitle: "Listnr is transcribing for scan-to-position") {
            preparationTask = Task { [weak self] in
                await self?.runPreparation(bookID: bookID, url: url)
            }
        }
    }

    func cancelPreparation() {
        preparationTask?.cancel()
    }

    private func runPreparation(bookID: UUID, url: URL) async {
        do {
            try Task.checkCancellation()
            let models = try await Transcriber.loadModels()
            let transcriber = self.transcriber ?? Transcriber()
            self.transcriber = transcriber
            try await transcriber.prepare(models: models)
            preparationFolderAccess = try securityScope(for: bookID)
            // A checkpoint means a stopped run: continue it instead of
            // starting over. Cancel keeps the checkpoint; only the final
            // write deletes it.
            let checkpoint = TranscriptCheckpoint.load(bookID: bookID)
            if let checkpoint, checkpoint.duration > 0 {
                preparationProgress = checkpoint.nextOffset / checkpoint.duration
            }
            _ = try await transcriber.transcribe(
                url: url, bookID: bookID,
                from: checkpoint?.nextOffset ?? 0,
                seed: checkpoint?.words ?? []
            ) { [weak self] fraction in
                Task { @MainActor in
                    self?.preparationProgress = fraction
                    self?.publishPillProgress(fraction)
                }
            }
            preparationProgress = nil
        } catch is CancellationError {
            preparationProgress = nil
        } catch {
            preparationProgress = nil
            preparationNotice = "This audiobook could not be prepared."
            NSLog("Listnr: transcription failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
        preparationFolderAccess?.end()
        preparationFolderAccess = nil
        preparationTask = nil
        let finished = TranscriptCheckpoint.load(bookID: bookID) == nil
        finishBackgroundTask(success: finished)
        if finished {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.resumeTaskID)
        } else {
            scheduleOvernightResume()
        }
    }

    private func securityScope(for bookID: UUID) throws -> FolderSource.Access? {
        guard let book = store.books.first(where: { $0.id == bookID }),
              let folderID = book.sourceFolderID,
              let folder = store.folder(id: folderID)
        else { return nil }
        return try folder.beginAccess()
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

    // MARK: background continuation (BGContinuedProcessingTask, iOS 26)

    static let continuedTaskID = "com.luisKisters.Listnr.transcribe"
    static let resumeTaskID = "com.luisKisters.Listnr.transcribe-resume"
    /// Set once by `ListnrApp` from `register`'s return value. Submitting an
    /// identifier with no registered handler raises an Objective-C exception
    /// Swift cannot catch, so these are hard gates.
    static var continuedRegistered = false
    static var resumeRegistered = false

    enum PendingWork {
        case download
        case prepare(bookID: UUID, url: URL)
    }

    private var pendingWork: PendingWork?
    private var backgroundTask: BGTask?

    /// True when the scheduler took the work: the registered handler will call
    /// `runPendingBackground`. False sends the caller down the in-app path.
    private func submitContinued(work: PendingWork, title: String, subtitle: String) -> Bool {
        guard Self.continuedRegistered else { return false }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedTaskID, title: title, subtitle: subtitle)
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            pendingWork = work
            return true
        } catch {
            return false
        }
    }

    /// The continued-processing handler. The work runs inside the task; expiry
    /// cancels it and the checkpoint on disk is the state.
    func runPendingBackground(task: BGTask) {
        guard let work = pendingWork else {
            task.setTaskCompleted(success: false)
            return
        }
        pendingWork = nil
        backgroundTask = task
        (task as? BGContinuedProcessingTask)?.progress.totalUnitCount = 100
        switch work {
        case .download:
            let running: Task<Void, Never> = Task { [weak self] in
                await self?.runModelDownload()
            }
            modelDownloadTask = running
            task.expirationHandler = { running.cancel() }
        case .prepare(let bookID, let url):
            let running: Task<Void, Never> = Task { [weak self] in
                await self?.runPreparation(bookID: bookID, url: url)
            }
            preparationTask = running
            task.expirationHandler = { running.cancel() }
        }
    }

    private func publishPillProgress(_ fraction: Double) {
        (backgroundTask as? BGContinuedProcessingTask)?
            .progress.completedUnitCount = Int64(min(max(fraction, 0), 1) * 100)
    }

    private func finishBackgroundTask(success: Bool) {
        backgroundTask?.setTaskCompleted(success: success)
        backgroundTask = nil
    }

    /// Called on every foreground: a checkpoint on disk is a stopped run, and
    /// a continued task may only be submitted from the foreground.
    func resumeCheckpointedPreparation() {
        guard modelDownload == .ready, preparationTask == nil, modelDownloadTask == nil,
              let book = store.books.first(where: {
                  !$0.isMissing && !$0.hasTranscript
                      && FileManager.default.fileExists(
                          atPath: TranscriptCheckpoint.url(for: $0.id).path)
              })
        else { return }
        prepareForScanning(bookID: book.id)
    }

    /// The overnight fallback: idle on the charger, minutes at a time — enough
    /// to advance a checkpointed book while the phone sleeps.
    private func scheduleOvernightResume() {
        guard Self.resumeRegistered else { return }
        let request = BGProcessingTaskRequest(identifier: Self.resumeTaskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The overnight handler: same preparation, no pill.
    func runOvernight(task: BGTask) {
        guard modelDownload == .ready, preparationTask == nil,
              let book = store.books.first(where: {
                  !$0.isMissing && !$0.hasTranscript
                      && FileManager.default.fileExists(
                          atPath: TranscriptCheckpoint.url(for: $0.id).path)
              }),
              let url = book.audioURL
        else {
            task.setTaskCompleted(success: true)
            return
        }
        backgroundTask = task
        let running: Task<Void, Never> = Task { [weak self] in
            await self?.runPreparation(bookID: book.id, url: url)
        }
        preparationTask = running
        task.expirationHandler = { running.cancel() }
    }

    /// The scan's confirmed jump: the matched book becomes the loaded one, the
    /// engine seeks, the position is persisted and the player is what the user
    /// lands on.
    func jumpFromScan(bookID: UUID, time: TimeInterval) {
        if bookID != currentBookID, let book = store.books.first(where: { $0.id == bookID }) {
            openInPlayer(book)
        }
        selectChapterTimestamp(time)
        tab = .audiobook
    }

    var notesForCurrentBook: [Note] {
        guard let id = currentBookID else { return [] }
        return store.notes[id] ?? []
    }
}