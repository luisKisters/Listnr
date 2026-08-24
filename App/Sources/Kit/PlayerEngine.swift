import Combine
import Foundation

/// The playback seam. Views talk to this protocol only, so UI tests and
/// previews run the deterministic mock while the device runs AVFoundation.
@MainActor
protocol PlayerEngine: AnyObject, ObservableObject {
    var isPlaying: Bool { get }
    var position: TimeInterval { get }
    var duration: TimeInterval { get }
    var speed: Double { get }
    /// Time left on the sleep timer; nil when none runs. Derived from a
    /// deadline, never decremented — a decrement drifts and stops counting
    /// while the app is suspended.
    var sleepRemaining: TimeInterval? { get }
    /// The choice the timer was armed with, so the picker can show which one
    /// is active without keeping a second copy of the truth.
    var sleepArmedMinutes: Int? { get }
    /// Fired on every state change worth repainting from.
    var onChange: (() -> Void)? { get set }

    func load(url: URL, startPosition: TimeInterval, speed: Double) throws
    func play()
    func pause()
    func togglePlay()
    func seek(to position: TimeInterval)
    func setSpeed(_ speed: Double)
    func skipBack(_ interval: TimeInterval)
    func skipForward(_ interval: TimeInterval)
    func armSleepTimer(minutes: Int?)
    func stop()
}

/// Deterministic engine for previews and tests. Time advances only when
/// `advance(by:)` is called — no hidden clocks anywhere, including the sleep
/// timer's, which reads the injectable `now` closure.
@MainActor
final class MockEngine: PlayerEngine, ObservableObject {
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var speed: Double = 1
    private(set) var sleepDeadline: Date?
    private(set) var sleepArmedMinutes: Int?
    var onChange: (() -> Void)?

    /// The clock the sleep deadline is measured against. `advance(by:)` moves
    /// it, so tests never wait on wall time.
    var now: () -> Date = Date.init

    var sleepRemaining: TimeInterval? {
        sleepDeadline.map { $0.timeIntervalSince(now()) }
    }

    func load(url: URL, startPosition: TimeInterval, speed: Double) throws {
        duration = Self.fixtureDurations[url.lastPathComponent] ?? 600
        position = min(max(startPosition, 0), duration)
        self.speed = speed
        emit()
    }

    func play() { isPlaying = true; emit() }
    func pause() { isPlaying = false; emit() }
    func togglePlay() { isPlaying ? pause() : play() }

    func seek(to position: TimeInterval) {
        self.position = min(max(position, 0), duration)
        emit()
    }

    func setSpeed(_ speed: Double) {
        self.speed = speed
        emit()
    }

    func skipBack(_ interval: TimeInterval) { seek(to: position - interval) }
    func skipForward(_ interval: TimeInterval) { seek(to: position + interval) }

    /// Arming is allowed while paused and never starts playback. Re-arming
    /// resets the deadline instead of stacking; nil clears it.
    func armSleepTimer(minutes: Int?) {
        guard let minutes, minutes > 0 else {
            sleepDeadline = nil
            sleepArmedMinutes = nil
            emit()
            return
        }
        sleepDeadline = now().addingTimeInterval(Double(minutes) * 60)
        sleepArmedMinutes = minutes
        emit()
    }

    func stop() {
        isPlaying = false
        position = 0
        sleepDeadline = nil
        sleepArmedMinutes = nil
        emit()
    }

    /// Test hook: move the clock, then playback, exactly as wall time would.
    /// The sleep deadline is wall-clock, so `seconds` is wall seconds and the
    /// position moves by `seconds * speed`.
    func advance(by seconds: TimeInterval) {
        let target = now().addingTimeInterval(seconds)
        now = { target }

        // A due deadline stops playback where it stood — it never ducks, and
        // it fires whether or not the book was playing.
        if fireSleepIfDue() {
            emit()
            return
        }
        guard isPlaying else {
            emit()
            return
        }
        position = min(duration, position + seconds * speed)
        if position >= duration { isPlaying = false }
        emit()
    }

    /// True when the timer was due and has just stopped playback.
    @discardableResult
    private func fireSleepIfDue() -> Bool {
        guard let deadline = sleepDeadline, deadline.timeIntervalSince(now()) <= 0 else {
            return false
        }
        sleepDeadline = nil
        sleepArmedMinutes = nil
        isPlaying = false
        return true
    }

    private func emit() { onChange?() }

    static let fixtureDurations = [
        "alpha.m4a": 96.0,
        "bravo.m4a": 120.0,
        "charlie.m4a": 72.0,
        // A ten-hour book, so sleep-timer tests never run out of audio before
        // the deadline they are testing.
        "long.m4a": 36_000.0,
    ]
}
