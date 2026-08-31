import XCTest

@testable import Listnr

/// The chunk math is pure, so it is tested without audio, without a model and
/// without a file. Windows never overlap: a word cut on a boundary is one bad
/// token per 300 s, which is cheaper than dedupe logic.
final class TranscriptChunkingTests: XCTestCase {
    private func pairs(_ windows: [ClosedRange<TimeInterval>]) -> [[TimeInterval]] {
        windows.map { [$0.lowerBound, $0.upperBound] }
    }

    func testExactDivision() {
        let w = Transcriber.windows(duration: 900, from: 0, window: 300)
        XCTAssertEqual(pairs(w), [[0, 300], [300, 600], [600, 900]])
    }

    func testRemainderBecomesAShortFinalWindow() {
        let w = Transcriber.windows(duration: 750, from: 0, window: 300)
        XCTAssertEqual(pairs(w), [[0, 300], [300, 600], [600, 750]])
    }

    func testResumingMidWindowStartsAtTheOffset() {
        let w = Transcriber.windows(duration: 900, from: 450, window: 300)
        XCTAssertEqual(pairs(w), [[450, 750], [750, 900]])
    }

    func testOffsetAtOrPastTheDurationYieldsNothing() {
        XCTAssertTrue(Transcriber.windows(duration: 900, from: 900, window: 300).isEmpty)
        XCTAssertTrue(Transcriber.windows(duration: 900, from: 1200, window: 300).isEmpty)
    }

    func testShorterThanOneWindowIsASingleWindow() {
        XCTAssertEqual(pairs(Transcriber.windows(duration: 45, from: 0, window: 300)), [[0, 45]])
    }

    func testWindowsAreContiguousAndCoverTheWholeBook() {
        let w = Transcriber.windows(duration: 100_000, from: 0, window: 300)
        XCTAssertEqual(w.first?.lowerBound, 0)
        XCTAssertEqual(w.last?.upperBound, 100_000)
        for (a, b) in zip(w, w.dropFirst()) {
            XCTAssertEqual(a.upperBound, b.lowerBound, "windows must not overlap or skip")
        }
    }

    func testZeroDurationYieldsNothing() {
        XCTAssertTrue(Transcriber.windows(duration: 0, from: 0, window: 300).isEmpty)
    }
}
