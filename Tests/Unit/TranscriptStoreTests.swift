import XCTest

@testable import Listnr

/// Pure file I/O in a temp directory: nothing here touches the real
/// Application Support folder.
final class TranscriptStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transcripts-\(UUID().uuidString)")
        TranscriptStore.directoryOverride = dir
    }

    override func tearDownWithError() throws {
        TranscriptStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func words(_ count: Int, from start: TimeInterval = 0) -> [TranscriptWord] {
        (0..<count).map { TranscriptWord(text: "w\($0)", start: start + Double($0) * 0.4) }
    }

    func testTranscriptRoundTripsIdentically() throws {
        let id = UUID()
        let transcript = Transcript(
            bookID: id, words: words(50), language: "en",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try TranscriptStore.save(transcript)
        XCTAssertEqual(TranscriptStore.load(bookID: id), transcript)
        XCTAssertTrue(TranscriptStore.exists(bookID: id))
    }

    func testCheckpointRoundTripsIdentically() throws {
        let id = UUID()
        let checkpoint = TranscriptCheckpoint(
            bookID: id, nextOffset: 600, duration: 2400, words: words(30))
        try TranscriptStore.saveCheckpoint(checkpoint)
        XCTAssertEqual(TranscriptStore.loadCheckpoint(bookID: id), checkpoint)
        XCTAssertEqual(checkpoint.fraction, 0.25, accuracy: 0.0001)
        // A checkpoint is not a transcript.
        XCTAssertFalse(TranscriptStore.exists(bookID: id))
        XCTAssertNil(TranscriptStore.load(bookID: id))
    }

    func testSavingTheTranscriptRemovesTheCheckpoint() throws {
        let id = UUID()
        try TranscriptStore.saveCheckpoint(
            TranscriptCheckpoint(bookID: id, nextOffset: 300, duration: 900, words: words(10)))
        XCTAssertNotNil(TranscriptStore.loadCheckpoint(bookID: id))

        try TranscriptStore.save(
            Transcript(bookID: id, words: words(40), language: nil, createdAt: Date()))
        XCTAssertNil(TranscriptStore.loadCheckpoint(bookID: id))
        XCTAssertTrue(TranscriptStore.exists(bookID: id))
    }

    func testRemoveDropsBothFiles() throws {
        let id = UUID()
        try TranscriptStore.saveCheckpoint(
            TranscriptCheckpoint(bookID: id, nextOffset: 300, duration: 900, words: words(10)))
        try TranscriptStore.save(
            Transcript(bookID: id, words: words(40), language: nil, createdAt: Date()))
        try TranscriptStore.saveCheckpoint(
            TranscriptCheckpoint(bookID: id, nextOffset: 600, duration: 900, words: words(20)))

        TranscriptStore.remove(bookID: id)
        XCTAssertFalse(TranscriptStore.exists(bookID: id))
        XCTAssertNil(TranscriptStore.load(bookID: id))
        XCTAssertNil(TranscriptStore.loadCheckpoint(bookID: id))
    }

    func testMissingFilesLoadAsNil() {
        let id = UUID()
        XCTAssertNil(TranscriptStore.load(bookID: id))
        XCTAssertNil(TranscriptStore.loadCheckpoint(bookID: id))
        XCTAssertFalse(TranscriptStore.exists(bookID: id))
    }
}
