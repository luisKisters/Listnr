import XCTest

@testable import Listnr

/// The sleep timer is a deadline, not a countdown. These tests drive
/// `MockEngine`'s injectable clock by hand, so nothing here waits on wall time.
@MainActor
final class SleepTimerTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    /// A ten-hour book, playing, on a frozen clock.
    private func makePlaying() -> MockEngine {
        let engine = MockEngine()
        let start = epoch
        engine.now = { start }
        try? engine.load(url: URL(fileURLWithPath: "/tmp/long.m4a"), startPosition: 0, speed: 1)
        engine.play()
        return engine
    }

    func testArmedTimerSurvivesUpToTheDeadline() {
        let engine = makePlaying()
        engine.armSleepTimer(minutes: 15)
        XCTAssertEqual(engine.sleepRemaining ?? 0, 900, accuracy: 0.001)

        engine.advance(by: 14 * 60 + 59)
        XCTAssertTrue(engine.isPlaying, "the timer must not fire one second early")
        XCTAssertEqual(engine.sleepRemaining ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(engine.position, 899, accuracy: 0.001)
    }

    func testDeadlineStopsPlayback() {
        let engine = makePlaying()
        engine.armSleepTimer(minutes: 15)
        engine.advance(by: 15 * 60 + 1)

        XCTAssertFalse(engine.isPlaying, "playback stops at the deadline, it never ducks")
        XCTAssertNil(engine.sleepRemaining)
        XCTAssertNil(engine.sleepArmedMinutes)
    }

    func testOffClearsTheDeadline() {
        let engine = makePlaying()
        engine.armSleepTimer(minutes: 30)
        XCTAssertNotNil(engine.sleepRemaining)

        engine.armSleepTimer(minutes: nil)
        XCTAssertNil(engine.sleepRemaining)
        XCTAssertNil(engine.sleepArmedMinutes)

        engine.advance(by: 60 * 60)
        XCTAssertTrue(engine.isPlaying, "a cleared timer must never fire")
    }

    func testReArmingResetsRatherThanStacks() {
        let engine = makePlaying()
        engine.armSleepTimer(minutes: 60)
        engine.advance(by: 10 * 60)
        XCTAssertEqual(engine.sleepRemaining ?? 0, 50 * 60, accuracy: 0.001)

        engine.armSleepTimer(minutes: 15)
        XCTAssertEqual(engine.sleepRemaining ?? 0, 15 * 60, accuracy: 0.001)
        XCTAssertEqual(engine.sleepArmedMinutes, 15)

        engine.advance(by: 15 * 60 + 1)
        XCTAssertFalse(engine.isPlaying, "the second arming is the one that counts")
    }

    func testArmingWhilePausedDoesNotStartPlayback() {
        let engine = makePlaying()
        engine.pause()
        engine.armSleepTimer(minutes: 15)

        XCTAssertFalse(engine.isPlaying, "arming a timer is not a play command")
        XCTAssertEqual(engine.sleepRemaining ?? 0, 900, accuracy: 0.001)
    }

    func testManualPauseLeavesTheTimerRunning() {
        let engine = makePlaying()
        engine.armSleepTimer(minutes: 15)
        engine.advance(by: 5 * 60)
        engine.pause()

        // The clock keeps running while the book is paused (mockup behaviour).
        engine.advance(by: 5 * 60)
        XCTAssertEqual(engine.sleepRemaining ?? 0, 5 * 60, accuracy: 0.001)
        XCTAssertEqual(engine.sleepArmedMinutes, 15)

        engine.advance(by: 5 * 60 + 1)
        XCTAssertNil(engine.sleepRemaining, "the deadline still passes while paused")
        XCTAssertFalse(engine.isPlaying)
    }

    func testRemainingIsNilWhenNoTimerRuns() {
        let engine = makePlaying()
        XCTAssertNil(engine.sleepRemaining)
        XCTAssertNil(engine.sleepArmedMinutes)
    }
}
