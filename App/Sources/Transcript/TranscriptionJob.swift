import BackgroundTasks
import Foundation
import SwiftUI

/// Owns the one transcription that may be running, and the three ways iOS lets
/// it keep running when the phone is locked:
///
/// - `BGContinuedProcessingTask` (iOS 26) is the primary: the user starts it in
///   the foreground and the system keeps it alive after lock, showing its own
///   progress pill with a cancel.
/// - `BGProcessingTask` is the overnight fallback for a job the system expired.
/// - the app's existing `audio` background mode keeps it alive for free while a
///   book plays.
///
/// The whole design rests on one rule: **every finished chunk is on disk**. The
/// job can be killed at any moment — expiry, thermal pressure, the user
/// cancelling from the pill — so a restart continues from the checkpoint and
/// the partial file is a feature, not damage.
@MainActor
final class TranscriptionJob: ObservableObject {
    enum State: Equatable {
        case idle
        case running(bookID: UUID, fraction: Double)
        case failed(bookID: UUID, reason: String)

        var runningBookID: UUID? {
            if case .running(let id, _) = self { return id }
            return nil
        }
    }

    enum ModelDownload: Equatable {
        case missing
        case downloading(fraction: Double)
        case ready
    }

    /// One fixed identifier, not `…transcribe.<bookID>` under a wildcard: on
    /// iOS 26.5 `register(forTaskWithIdentifier: "…transcribe.*")` returns
    /// false, and submitting an unregistered identifier kills the app. Only one
    /// job runs at a time anyway, so `pendingBookID` says which book it is for.
    /// See `docs/IDEAS.md`.
    static let continuedIdentifier = "com.luisKisters.Listnr.transcribe"
    static let resumeIdentifier = "com.luisKisters.Listnr.transcribe-resume"

    /// Set once by `ListnrApp` from `register`'s return value. Submitting an
    /// identifier with no registered handler raises an Objective-C exception
    /// that Swift's `try` cannot catch, so this is a hard gate, not a hint.
    @MainActor static var continuedRegistered = false
    @MainActor static var resumeRegistered = false

    @Published private(set) var state: State = .idle
    @Published private(set) var model: ModelDownload = .missing
    /// A visible reason, in the shape `AppModel.playbackNotice` uses. Never a
    /// silent failure.
    @Published private(set) var notice: String?

    private let transcriber: any Transcribing
    private let book: @MainActor (UUID) -> Book?
    private let beginAccess: @MainActor (Book) throws -> FolderSource.Access?

    private var work: Task<Void, Never>?
    private var modelWork: Task<Void, Never>?
    /// The book a submitted continued-processing task belongs to. One
    /// identifier serves every book, so the handler needs this to know which.
    private var pendingBookID: UUID?
    private var pendingDownload = false
    private var modelTask: BGTask?

    init(
        transcriber: any Transcribing,
        book: @escaping @MainActor (UUID) -> Book?,
        beginAccess: @escaping @MainActor (Book) throws -> FolderSource.Access?
    ) {
        self.transcriber = transcriber
        self.book = book
        self.beginAccess = beginAccess
        model = transcriber.modelsReady ? .ready : .missing
    }

    /// Used by the launch arguments that drive the UI tests and the evidence
    /// screenshots; nothing in the app calls it.
    func overrideModel(_ value: ModelDownload) { model = value }

    // MARK: the speech model

    /// The download rides the same continued-processing task as a book, so it
    /// keeps going when the phone is locked. When the scheduler refuses, it
    /// runs in the app and pauses whenever the app leaves the foreground.
    func downloadModel() {
        guard modelWork == nil, model != .ready, state.runningBookID == nil else { return }
        model = .downloading(fraction: 0)
        notice = nil

        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIdentifier,
            title: "Downloading speech model",
            subtitle: "1.2 GB, once per phone")
        request.strategy = .queue

        guard Self.continuedRegistered else {
            notice = "Downloading in the app only — keep Listnr open."
            runModelDownload(task: nil)
            return
        }
        do {
            try BGTaskScheduler.shared.submit(request)
            pendingDownload = true
        } catch {
            notice = "Downloading in the app only — keep Listnr open."
            runModelDownload(task: nil)
        }
    }

    private func runModelDownload(task: BGTask?) {
        (task as? BGContinuedProcessingTask)?.progress.totalUnitCount = 100
        modelTask = task
        let running = Task { [transcriber] in
            do {
                try await transcriber.downloadModels { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.model else { return }
                        self.model = .downloading(fraction: fraction)
                        (self.modelTask as? BGContinuedProcessingTask)?
                            .progress.completedUnitCount = Int64(fraction * 100)
                    }
                }
                self.model = .ready
                self.modelTask?.setTaskCompleted(success: true)
            } catch {
                self.model = .missing
                if !Task.isCancelled {
                    self.notice = "The speech model could not be downloaded: \(error.localizedDescription)"
                }
                self.modelTask?.setTaskCompleted(success: false)
            }
            self.modelTask = nil
            self.modelWork = nil
        }
        modelWork = running
        // Expiry keeps the files FluidAudio already fetched; the next tap
        // continues from them.
        task?.expirationHandler = { running.cancel() }
    }

    func stopModelDownload() {
        modelWork?.cancel()
        modelWork = nil
        modelTask?.setTaskCompleted(success: false)
        modelTask = nil
        model = transcriber.modelsReady ? .ready : .missing
    }

    // MARK: starting

    /// Submits a continued-processing task and runs the work inside it. When
    /// the scheduler refuses — the simulator always does — the work still runs,
    /// it just pauses whenever the app leaves the foreground.
    func start(bookID: UUID) {
        guard model == .ready else {
            notice = "The speech model has to finish downloading first."
            return
        }
        if let running = state.runningBookID {
            let title = book(running)?.title ?? "a book"
            notice = "Already preparing \(title)."
            return
        }
        guard let target = book(bookID), !target.isMissing else { return }
        notice = nil

        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIdentifier,
            title: "Preparing \(target.title)",
            subtitle: "Listnr is transcribing for scan-to-position")
        request.strategy = .queue

        pendingBookID = bookID
        guard Self.continuedRegistered else {
            notice = "Preparing in the app only — keep Listnr open."
            run(bookID: bookID, task: nil)
            return
        }
        do {
            try BGTaskScheduler.shared.submit(request)
            // The handler registered in ListnrApp calls runPending(task:).
            state = .running(bookID: bookID, fraction: fractionOnDisk(for: target))
        } catch {
            // The simulator always lands here, and so does a phone that refuses
            // the submission. The work still happens; it just pauses when the
            // app leaves the foreground, and the checkpoint keeps it honest.
            notice = "Preparing in the app only — keep Listnr open."
            run(bookID: bookID, task: nil)
        }
    }

    /// The continued-processing handler: one identifier, so what it is for
    /// comes from `pendingDownload` / `pendingBookID`.
    func runPending(task: BGTask) {
        if pendingDownload {
            pendingDownload = false
            runModelDownload(task: task)
            return
        }
        guard let bookID = pendingBookID else {
            task.setTaskCompleted(success: false)
            return
        }
        run(bookID: bookID, task: task)
    }

    /// "Stop" is "pause": the checkpoint stays, so the next start continues.
    func stop(bookID: UUID) {
        guard state.runningBookID == bookID else { return }
        work?.cancel()
        work = nil
        state = .idle
        scheduleOvernightResume(bookID: bookID)
    }

    // MARK: running

    /// Everything one run mutates, in one main-actor box. The transcriber's
    /// `onChunk` is `@Sendable`, so it may not capture loose `var`s or a
    /// non-Sendable `BGTask`; it captures this reference instead.
    @MainActor
    private final class Run {
        var words: [TranscriptWord]
        var lastOffset: TimeInterval
        var chunkStarted = Date()
        /// Only a continued-processing task reports progress. The overnight
        /// `BGProcessingTask` has none, so these calls become no-ops.
        let pill: BGContinuedProcessingTask?
        let access: FolderSource.Access?

        init(
            words: [TranscriptWord], lastOffset: TimeInterval,
            pill: BGContinuedProcessingTask?, access: FolderSource.Access?
        ) {
            self.words = words
            self.lastOffset = lastOffset
            self.pill = pill
            self.access = access
        }
    }

    /// The one path every entry point funnels into: the foreground start, the
    /// continued-processing handler, and the overnight processing handler.
    func run(bookID: UUID, task: BGTask?) {
        guard state.runningBookID == nil || state.runningBookID == bookID else {
            task?.setTaskCompleted(success: false)
            return
        }
        guard let target = book(bookID), !target.isMissing, let url = target.audioURL else {
            task?.setTaskCompleted(success: false)
            return
        }
        // Same rule playback uses: an iCloud file that is not down yet cannot
        // be read, and saying so beats failing silently (plan risk 3).
        guard AppModel.ensureLocal(url) else {
            notice = "Downloading from iCloud — this book transcribes once the file is local."
            task?.setTaskCompleted(success: false)
            return
        }

        let access: FolderSource.Access?
        do {
            access = try beginAccess(target)
        } catch {
            notice = "This folder needs to be picked again."
            task?.setTaskCompleted(success: false)
            return
        }

        let checkpoint = TranscriptStore.loadCheckpoint(bookID: bookID)
        let duration = target.duration
        let from = checkpoint?.nextOffset ?? 0
        let title = target.title
        let run = Run(
            words: checkpoint?.words ?? [], lastOffset: from,
            pill: task as? BGContinuedProcessingTask, access: access)

        run.pill?.progress.totalUnitCount = Int64(max(duration, 1))
        run.pill?.progress.completedUnitCount = Int64(from)
        state = .running(bookID: bookID, fraction: duration > 0 ? from / duration : 0)

        let running = Task { [transcriber] in
            do {
                try await transcriber.transcribe(
                    url: url, duration: duration, from: from
                ) { chunkWords, nextOffset in
                    await MainActor.run {
                        let elapsed = Date().timeIntervalSince(run.chunkStarted)
                        let audio = nextOffset - run.lastOffset
                        run.words.append(contentsOf: chunkWords)
                        try? TranscriptStore.saveCheckpoint(
                            TranscriptCheckpoint(
                                bookID: bookID, nextOffset: nextOffset,
                                duration: duration, words: run.words))
                        run.pill?.progress.completedUnitCount = Int64(nextOffset)
                        let fraction = duration > 0 ? min(nextOffset / duration, 1) : 1
                        self.state = .running(bookID: bookID, fraction: fraction)
                        run.pill?.updateTitle(
                            "Preparing \(title)",
                            subtitle: "Transcribing · \(Int((fraction * 100).rounded())) %")
                        if elapsed > 0, audio > 0 {
                            TranscriptionEstimate.record(speed: audio / elapsed)
                        }
                        run.chunkStarted = Date()
                        run.lastOffset = nextOffset
                    }
                }
            } catch {
                await MainActor.run {
                    run.access?.end()
                    self.work = nil
                    self.state = .failed(bookID: bookID, reason: error.localizedDescription)
                    self.scheduleOvernightResume(bookID: bookID)
                    task?.setTaskCompleted(success: false)
                }
                return
            }

            await MainActor.run {
                run.access?.end()
                self.work = nil
                if run.lastOffset < duration {
                    // Cancelled or expired: the checkpoint on disk is the state.
                    self.state = .idle
                    self.scheduleOvernightResume(bookID: bookID)
                    task?.setTaskCompleted(success: false)
                    return
                }
                do {
                    try TranscriptStore.save(
                        Transcript(
                            bookID: bookID, words: run.words, language: nil, createdAt: Date()))
                    self.state = .idle
                    self.cancelOvernightResume()
                    task?.setTaskCompleted(success: true)
                } catch {
                    self.state = .failed(bookID: bookID, reason: error.localizedDescription)
                    task?.setTaskCompleted(success: false)
                }
            }
        }
        work = running
        // Expiry is not an error: cancel the Swift task and let the checkpoint
        // that is already on disk be the state.
        task?.expirationHandler = { running.cancel() }
    }

    // MARK: resume

    /// Called on every foreground. A continued-processing task may only be
    /// submitted from the foreground, so this is where a job that was expired
    /// or cancelled picks itself back up.
    func resumeIfNeeded(books: [Book]) {
        guard state.runningBookID == nil, model == .ready else { return }
        guard let pending = books.first(where: {
            !$0.isMissing && TranscriptStore.loadCheckpoint(bookID: $0.id) != nil
        }) else { return }
        start(bookID: pending.id)
    }

    /// The overnight fallback: a plain processing task, external power only, so
    /// a book that thermally expired still advances on the charger.
    func scheduleOvernightResume(bookID: UUID) {
        guard Self.resumeRegistered, TranscriptStore.loadCheckpoint(bookID: bookID) != nil
        else { return }
        let request = BGProcessingTaskRequest(identifier: Self.resumeIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    func cancelOvernightResume() {
        guard Self.resumeRegistered else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.resumeIdentifier)
    }

    /// The handler for the overnight task: pick the one book with a checkpoint
    /// and advance it, then re-arm if it did not finish.
    func runOvernight(task: BGTask, books: [Book]) {
        guard let pending = books.first(where: {
            !$0.isMissing && TranscriptStore.loadCheckpoint(bookID: $0.id) != nil
        }) else {
            task.setTaskCompleted(success: true)
            return
        }
        run(bookID: pending.id, task: task)
    }

    private func fractionOnDisk(for target: Book) -> Double {
        TranscriptStore.loadCheckpoint(bookID: target.id)?.fraction ?? 0
    }
}
