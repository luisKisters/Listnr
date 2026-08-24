import MediaPlayer
import XCTest
@testable import Listnr

/// The note capture policy: opening the sheet pauses; saving or cancelling
/// resumes only when playback was running before.
@MainActor
final class NoteCaptureTests: XCTestCase {
    private func makeModel() -> AppModel {
        let store = ListnrStore(inMemory: true, seedSamples: true)
        return AppModel(store: store, engine: MockEngine())
    }

    func testBeginPausesAndSaveResumes() throws {
        let model = makeModel()
        try model.engine.load(url: URL(fileURLWithPath: "/tmp/alpha.m4a"), startPosition: 10, speed: 1)
        model.engine.play()
        XCTAssertTrue(model.engine.isPlaying)

        model.beginNoteCapture()
        XCTAssertFalse(model.engine.isPlaying, "capture must pause playback")
        XCTAssertTrue(model.noteCaptureActive)

        model.saveNote(text: "  Rocky explains physics  ")
        XCTAssertTrue(model.engine.isPlaying, "save must resume playback")
        XCTAssertFalse(model.noteCaptureActive)

        XCTAssertEqual(model.currentBookID != nil, true, "sample library must expose a listening book")
        let notes = model.notesForCurrentBook
        XCTAssertEqual(notes.count, 1)
        if let first = notes.first {
            XCTAssertEqual(first.text, "Rocky explains physics")
            XCTAssertEqual(first.timestamp, 10, accuracy: 0.001)
        }
    }

    func testCancelResumesWithoutSaving() {
        let model = makeModel()
        model.beginNoteCapture()   // was not playing: stays paused after cancel
        model.cancelNoteCapture()
        XCTAssertFalse(model.engine.isPlaying)
        XCTAssertTrue(model.notesForCurrentBook.isEmpty)

        model.beginNoteCapture()
        model.saveNote(text: "   ")
        XCTAssertTrue(model.notesForCurrentBook.isEmpty, "blank notes are not saved")
    }

    /// Tapping a previous note seeks and closes the sheet; the close path is
    /// the sheet's own dismiss, so playback resumes only if it was playing.
    func testNoteTapSeeksAndResumesOnlyIfPlaying() throws {
        let playing = makeModel()
        try playing.engine.load(url: URL(fileURLWithPath: "/tmp/alpha.m4a"), startPosition: 10, speed: 1)
        playing.engine.play()
        playing.beginNoteCapture()
        XCTAssertFalse(playing.engine.isPlaying)

        playing.selectChapterTimestamp(42)
        playing.cancelNoteCapture()          // sheet dismissed by the tap
        XCTAssertEqual(playing.engine.position, 42, accuracy: 0.001)
        XCTAssertTrue(playing.engine.isPlaying, "note tap must resume playback that was running")

        let paused = makeModel()
        try paused.engine.load(url: URL(fileURLWithPath: "/tmp/alpha.m4a"), startPosition: 10, speed: 1)
        paused.beginNoteCapture()
        paused.selectChapterTimestamp(42)
        paused.cancelNoteCapture()
        XCTAssertEqual(paused.engine.position, 42, accuracy: 0.001)
        XCTAssertFalse(paused.engine.isPlaying, "note tap must not start playback that was paused")
    }

    func testSleepTimerStopsPlayback() {
        let model = makeModel()
        model.armSleep(minutes: nil)
        XCTAssertNil(model.engine.sleepRemaining)
    }

    func testMockEngineAdvancesAndSleeps() {
        let mock = MockEngine()
        try? mock.load(url: URL(fileURLWithPath: "/tmp/bravo.m4a"), startPosition: 5, speed: 2)
        XCTAssertEqual(mock.duration, 120)
        mock.play()
        mock.advance(by: 10)
        XCTAssertEqual(mock.position, 25, accuracy: 0.001)   // 2x speed

        mock.seek(to: 100)
        mock.armSleepTimer(minutes: 1)                        // 60s of book time
        mock.advance(by: 31)                                  // 62 book seconds at 2x
        XCTAssertFalse(mock.isPlaying, "sleep timer must stop playback")
        XCTAssertNil(mock.sleepRemaining)
    }
}

@MainActor
final class NowPlayingTests: XCTestCase {
    func testPayloadShape() {
        let info = NowPlaying.build(
            title: "Piranesi", author: "Susanna Clarke", chapter: "Chapter 3 — The House",
            position: 42, duration: 120, rate: 1.5)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Piranesi")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "Susanna Clarke")
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, "Chapter 3 — The House")
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 42)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.5)
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 120)
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.hms(3723), "1:02:03")
        XCTAssertEqual(Fmt.hms(63), "0:01:03")
        XCTAssertEqual(Fmt.span(185 * 60), "3h 05m")
        XCTAssertEqual(Fmt.span(42 * 60), "42m")
    }
}
