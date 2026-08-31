import XCTest
@testable import Listnr

final class TranscriptTests: XCTestCase {
    private var bookID = UUID()

    override func setUp() {
        super.setUp()
        bookID = UUID()
        let id = bookID
        addTeardownBlock { Transcript.delete(bookID: id) }
    }

    private func makeBook() -> Book {
        Book(id: bookID, title: "t", author: "a", formats: [.audio])
    }

    func testSaveThenLoadRoundTripsWordsTimesLanguageAndDate() throws {
        let words = [
            TranscriptWord(text: "Prolog", start: 0),
            TranscriptWord(text: "die", start: 0.42),
            TranscriptWord(text: "Tiefsee", start: 0.84),
            TranscriptWord(text: "Schätzing", start: 7.5),
        ]
        let transcript = Transcript(
            bookID: bookID, words: words, language: "de",
            createdAt: Date(timeIntervalSince1970: 1_770_000_000))

        try transcript.save()
        let loaded = try XCTUnwrap(Transcript.load(bookID: bookID))

        XCTAssertEqual(loaded, transcript)
        XCTAssertEqual(loaded.words.map(\.text), words.map(\.text))
        XCTAssertEqual(loaded.words.map(\.start), words.map(\.start))
        XCTAssertEqual(loaded.language, "de")
        XCTAssertEqual(loaded.createdAt, transcript.createdAt)
    }

    func testCheckpointRoundTripsAndDeletesWithTheTranscript() throws {
        let checkpoint = TranscriptCheckpoint(
            bookID: bookID, nextOffset: 596, duration: 3_600,
            words: [TranscriptWord(text: "bis", start: 595.2)])
        try checkpoint.save()
        XCTAssertEqual(TranscriptCheckpoint.load(bookID: bookID), checkpoint)

        Transcript.delete(bookID: bookID)
        XCTAssertNil(TranscriptCheckpoint.load(bookID: bookID))
    }

    func testFinalWriteRemovesTheCheckpoint() throws {
        try TranscriptCheckpoint(
            bookID: bookID, nextOffset: 596, duration: 3_600, words: []
        ).save()
        try Transcriber.write(Transcript(
            bookID: bookID, words: [], language: nil, createdAt: Date()))
        XCTAssertNil(TranscriptCheckpoint.load(bookID: bookID))
        XCTAssertNotNil(Transcript.load(bookID: bookID))
    }

    func testHasTranscriptReflectsTheFileOnDisk() throws {
        XCTAssertFalse(makeBook().hasTranscript)
        try Transcript(
            bookID: bookID, words: [TranscriptWord(text: "x", start: 0)],
            language: nil, createdAt: Date()
        ).save()
        XCTAssertTrue(makeBook().hasTranscript)
    }

    func testDeletingABookDeletesItsTranscriptAndHasTranscriptFollows() throws {
        try Transcript(
            bookID: bookID, words: [TranscriptWord(text: "x", start: 0)],
            language: nil, createdAt: Date()
        ).save()
        XCTAssertTrue(makeBook().hasTranscript)

        Transcript.delete(bookID: bookID)

        XCTAssertNil(Transcript.load(bookID: bookID))
        XCTAssertFalse(makeBook().hasTranscript)
    }

    func testDeletingAnAbsentTranscriptIsANoopSoMissingMeansNotPrepared() {
        Transcript.delete(bookID: bookID)
        XCTAssertNil(Transcript.load(bookID: bookID))
        XCTAssertFalse(makeBook().hasTranscript)
    }
}
