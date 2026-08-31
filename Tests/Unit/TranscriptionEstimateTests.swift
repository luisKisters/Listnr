import XCTest

@testable import Listnr

/// The three boundaries of the estimate line, plus the speed store.
final class TranscriptionEstimateTests: XCTestCase {
    func testUnderAMinute() {
        // 40 s of audio at 80x is half a second.
        XCTAssertEqual(TranscriptionEstimate.text(duration: 40, speed: 80), "under a minute")
        // Exactly at the rounding boundary: 29 s of work rounds to 0 min.
        XCTAssertEqual(TranscriptionEstimate.text(duration: 29 * 80, speed: 80), "under a minute")
    }

    func testMinutesOnly() {
        XCTAssertEqual(TranscriptionEstimate.text(duration: 30 * 80, speed: 80), "about 1 min")
        // 27 h 55 min at 80x is about 21 min — the mockup's book job.
        XCTAssertEqual(TranscriptionEstimate.text(duration: 100_500, speed: 80), "about 21 min")
        XCTAssertEqual(TranscriptionEstimate.text(duration: 59 * 60 * 80, speed: 80), "about 59 min")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(TranscriptionEstimate.text(duration: 60 * 60 * 80, speed: 80), "about 1 h 0 min")
        XCTAssertEqual(TranscriptionEstimate.text(duration: 95 * 60 * 80, speed: 80), "about 1 h 35 min")
    }

    /// The book's own length reads as the mockup writes it: `27 h 55 min`.
    func testDurationReadsLikeTheMockup() {
        XCTAssertEqual(TranscriptionEstimate.duration(100_500), "27 h 55 min")
        XCTAssertEqual(TranscriptionEstimate.duration(45 * 60), "45 min")
        XCTAssertEqual(TranscriptionEstimate.duration(3600), "1 h 0 min")
        XCTAssertEqual(TranscriptionEstimate.duration(0), "0 min")
    }

    func testDegenerateInputsNeverCrash() {
        XCTAssertEqual(TranscriptionEstimate.text(duration: 0, speed: 80), "under a minute")
        XCTAssertEqual(TranscriptionEstimate.text(duration: 3600, speed: 0), "under a minute")
    }

    func testSpeedFallsBackUntilSomethingIsMeasured() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "estimate-\(UUID().uuidString)"))
        XCTAssertEqual(TranscriptionEstimate.speed(in: defaults), 80)

        TranscriptionEstimate.record(speed: 40, in: defaults)
        XCTAssertEqual(TranscriptionEstimate.speed(in: defaults), 40, accuracy: 0.001)

        // Later measurements blend, so one slow chunk cannot swing the number.
        TranscriptionEstimate.record(speed: 140, in: defaults)
        XCTAssertEqual(TranscriptionEstimate.speed(in: defaults), 70, accuracy: 0.001)

        TranscriptionEstimate.record(speed: -5, in: defaults)
        XCTAssertEqual(TranscriptionEstimate.speed(in: defaults), 70, accuracy: 0.001)
    }
}
