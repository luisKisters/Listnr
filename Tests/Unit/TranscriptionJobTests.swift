import XCTest

@testable import Listnr

/// The controller, driven by `FakeTranscriber` and with `task: nil` — the
/// simulator has no `BGTaskScheduler`, and the scheduler is not what these
/// tests are about. What they prove is the checkpoint contract: every chunk is
/// on disk, a cancel keeps it, and only a finished run writes the final file.
@MainActor
final class TranscriptionJobTests: XCTestCase {
    private var dir: URL!
    private var books: [Book] = []

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("job-\(UUID().uuidString)")
        TranscriptStore.directoryOverride = dir
        books = []
    }

    override func tearDownWithError() throws {
        TranscriptStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// A book whose file need not exist: `ensureLocal` only refuses iCloud
    /// items that are still downloading, and the fake never opens the URL.
    private func makeBook(duration: TimeInterval, title: String = "Book") -> Book {
        let book = Book(
            id: UUID(), title: title, author: "Author", formats: [.audio],
            audioURL: dir.appendingPathComponent("\(title).m4b"), duration: duration)
        books.append(book)
        return book
    }

    private func makeJob(_ transcriber: FakeTranscriber) -> TranscriptionJob {
        TranscriptionJob(
            transcriber: transcriber,
            book: { [weak self] id in self?.books.first { $0.id == id } },
            beginAccess: { _ in nil })
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: a clean run

    func testRunFromZeroWritesTheFinalFileAndDropsTheCheckpoint() async throws {
        let book = makeBook(duration: 900)          // three 300 s windows
        let job = makeJob(FakeTranscriber(wordsPerChunk: 3))

        job.run(bookID: book.id, task: nil)
        try await waitUntil("the run to finish") { job.state == .idle }

        let transcript = try XCTUnwrap(TranscriptStore.load(bookID: book.id))
        XCTAssertEqual(transcript.words.count, 9)
        XCTAssertEqual(transcript.words.first?.start, 0)
        XCTAssertEqual(transcript.words.last?.start, 602)
        XCTAssertNil(TranscriptStore.loadCheckpoint(bookID: book.id))
    }

    func testRunFromACheckpointResumesAndKeepsTheEarlierWords() async throws {
        let book = makeBook(duration: 900)
        let earlier = [TranscriptWord(text: "already", start: 12)]
        try TranscriptStore.saveCheckpoint(
            TranscriptCheckpoint(
                bookID: book.id, nextOffset: 300, duration: 900, words: earlier))

        let job = makeJob(FakeTranscriber(wordsPerChunk: 2))
        job.run(bookID: book.id, task: nil)
        try await waitUntil("the resumed run to finish") { job.state == .idle }

        let transcript = try XCTUnwrap(TranscriptStore.load(bookID: book.id))
        // One kept word plus two windows of two: nothing before 300 s is redone.
        XCTAssertEqual(transcript.words.count, 5)
        XCTAssertEqual(transcript.words.first, earlier[0])
        XCTAssertEqual(transcript.words[1].start, 300)
    }

    // MARK: interruption

    func testCancelMidRunKeepsTheCheckpointAndWritesNoFinalFile() async throws {
        let book = makeBook(duration: 3_000)        // ten windows
        let job = makeJob(FakeTranscriber(wordsPerChunk: 1, chunkDelay: .milliseconds(40)))

        job.run(bookID: book.id, task: nil)
        try await waitUntil("the first checkpoint") {
            TranscriptStore.loadCheckpoint(bookID: book.id) != nil
        }
        job.stop(bookID: book.id)

        let checkpoint = try XCTUnwrap(TranscriptStore.loadCheckpoint(bookID: book.id))
        XCTAssertGreaterThan(checkpoint.nextOffset, 0)
        XCTAssertLessThan(checkpoint.nextOffset, 3_000)
        XCTAssertFalse(TranscriptStore.exists(bookID: book.id))
        XCTAssertEqual(job.state, .idle)
    }

    func testAThrowingTranscriberFailsWithTheCheckpointIntact() async throws {
        let book = makeBook(duration: 900)
        let job = makeJob(FakeTranscriber(wordsPerChunk: 2, failOnChunk: 1))

        job.run(bookID: book.id, task: nil)
        try await waitUntil("the failure") {
            if case .failed = job.state { return true }
            return false
        }

        guard case .failed(let id, let reason) = job.state else {
            return XCTFail("expected a failed state, got \(job.state)")
        }
        XCTAssertEqual(id, book.id)
        XCTAssertFalse(reason.isEmpty)
        // The first window survived; only the second threw.
        let checkpoint = try XCTUnwrap(TranscriptStore.loadCheckpoint(bookID: book.id))
        XCTAssertEqual(checkpoint.nextOffset, 300)
        XCTAssertEqual(checkpoint.words.count, 2)
        XCTAssertFalse(TranscriptStore.exists(bookID: book.id))
    }

    // MARK: one job at a time

    func testStartingASecondBookWhileOneRunsIsRefusedWithAReason() async throws {
        let first = makeBook(duration: 3_000, title: "First")
        let second = makeBook(duration: 900, title: "Second")
        let job = makeJob(FakeTranscriber(chunkDelay: .milliseconds(40)))

        job.run(bookID: first.id, task: nil)
        XCTAssertEqual(job.state.runningBookID, first.id)

        job.start(bookID: second.id)
        XCTAssertEqual(job.notice, "Already preparing First.")
        XCTAssertEqual(job.state.runningBookID, first.id)
        XCTAssertNil(TranscriptStore.loadCheckpoint(bookID: second.id))

        job.stop(bookID: first.id)
    }

    func testStartingBeforeTheModelIsReadySaysSo() {
        let book = makeBook(duration: 900)
        let job = makeJob(FakeTranscriber(modelsReady: false))

        job.start(bookID: book.id)
        XCTAssertEqual(job.notice, "The speech model has to finish downloading first.")
        XCTAssertEqual(job.state, .idle)
    }
}
