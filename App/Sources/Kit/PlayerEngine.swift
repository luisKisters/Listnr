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
    /// Set when a sleep timer runs; nil when it does not.
    var sleepRemaining: TimeInterval? { get }
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
/// `advance(by:)` is called — no hidden clocks anywhere.
@MainActor
final class MockEngine: PlayerEngine, ObservableObject {
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var speed: Double = 1
    private(set) var sleepRemaining: TimeInterval?
    var onChange: (() -> Void)?

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

    func armSleepTimer(minutes: Int?) {
        sleepRemaining = minutes.map { Double($0) * 60 }
        emit()
    }

    func stop() {
        isPlaying = false
        position = 0
        emit()
    }

    /// Test hook: simulate wall-clock playback.
    func advance(by seconds: TimeInterval) {
        guard isPlaying else { return }
        let step = seconds * speed
        if let sleep = sleepRemaining {
            sleepRemaining = sleep - step
            if sleepRemaining ?? 0 <= 0 {
                sleepRemaining = nil
                isPlaying = false
                emit()
                return
            }
        }
        position = min(duration, position + step)
        if position >= duration { isPlaying = false }
        emit()
    }

    private func emit() { onChange?() }

    static let fixtureDurations = [
        "alpha.m4a": 96.0,
        "bravo.m4a": 120.0,
        "charlie.m4a": 72.0,
    ]
}
