import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// The real engine: AVAudioPlayer inside an audio-session-configured app with
/// lock-screen controls. All mutable state is main-actor bound; the player's
/// completion callback hops back to the main actor.
@MainActor
final class AudioPlayerEngine: NSObject, PlayerEngine, ObservableObject {
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var speed: Double = 1
    /// The sleep timer is a deadline, not a countdown: a decrement drifts and
    /// stops counting while the app is suspended, a deadline does neither.
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var sleepArmedMinutes: Int?
    var onChange: (() -> Void)?

    var sleepRemaining: TimeInterval? {
        sleepDeadline.map { $0.timeIntervalSinceNow }
    }

    /// `nonisolated(unsafe)`: written once in `init`, read once in `deinit`.
    private nonisolated(unsafe) var activeObserver: (any NSObjectProtocol)?

    override init() {
        super.init()
        configureAudioSession()
        registerRemoteCommands()
        // Coming back from a suspension is the other moment the deadline can
        // be overdue — the ticker was not running while we were away.
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.fireSleepIfDue() }
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    // MARK: session + remote

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            // Playback still works in the foreground; background audio may not.
            NSLog("Listnr: audio session setup failed: \(error.localizedDescription)")
        }
    }

    private var remoteHandlers: [Any] = []

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        remoteHandlers.append(
            center.playCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.play() }
                return .success
            })
        remoteHandlers.append(
            center.pauseCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
                return .success
            })
        remoteHandlers.append(
            center.togglePlayPauseCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.togglePlay() }
                return .success
            })
        remoteHandlers.append(
            center.skipBackwardCommand.addTarget { [weak self] event in
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
                MainActor.assumeIsolated { self?.skipBack(interval) }
                return .success
            })
        remoteHandlers.append(
            center.skipForwardCommand.addTarget { [weak self] event in
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
                MainActor.assumeIsolated { self?.skipForward(interval) }
                return .success
            })
        remoteHandlers.append(
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
                return .success
            })
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.preferredIntervals = [30]
    }

    // MARK: PlayerEngine

    func load(url: URL, startPosition: TimeInterval, speed: Double) throws {
        stopTicker()
        let p = try AVAudioPlayer(contentsOf: url)
        p.delegate = self
        p.enableRate = true
        p.rate = Float(speed)
        p.prepareToPlay()
        player = p
        duration = p.duration
        position = min(max(startPosition, 0), p.duration)
        self.speed = speed
        isPlaying = false
        // A timer armed before the book loaded keeps running.
        syncTicker()
        emit()
    }

    func play() {
        guard !isPlaying else { return }
        player?.rate = Float(speed)
        player?.play()
        isPlaying = true
        syncTicker()
        emit()
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        player?.rate = Float(speed)
        isPlaying = false
        syncTicker()
        emit()
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to position: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(position, 0), player.duration - 0.05)
        self.position = player.currentTime
        emit()
    }

    func setSpeed(_ speed: Double) {
        self.speed = speed
        player?.enableRate = true
        player?.rate = Float(speed)
        emit()
    }

    func skipBack(_ interval: TimeInterval) {
        seek(to: position - interval)
    }

    func skipForward(_ interval: TimeInterval) {
        seek(to: position + interval)
    }

    /// Arming while paused is allowed and does not start playback; re-arming
    /// resets the deadline instead of stacking. nil is "Off".
    func armSleepTimer(minutes: Int?) {
        guard let minutes, minutes > 0 else {
            sleepDeadline = nil
            sleepArmedMinutes = nil
            syncTicker()
            emit()
            return
        }
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepArmedMinutes = minutes
        syncTicker()
        emit()
    }

    func stop() {
        stopTicker()
        player?.stop()
        player = nil
        isPlaying = false
        position = 0
        duration = 0
        sleepDeadline = nil
        sleepArmedMinutes = nil
        emit()
    }

    // MARK: ticking

    /// The ticker runs while playing and while a deadline is armed — a timer
    /// armed on a paused book still has to count down and still has to fire.
    private func syncTicker() {
        if isPlaying || sleepDeadline != nil {
            if ticker == nil { startTicker() }
        } else {
            stopTicker()
        }
    }

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        if let player { position = player.currentTime }
        if fireSleepIfDue() { return }
        emit()
    }

    /// Stops playback the moment the deadline passes — it stops, it never
    /// ducks. `pause()` emits, so the model persists the position and repaints
    /// the lock screen with a paused book.
    @discardableResult
    private func fireSleepIfDue() -> Bool {
        guard let deadline = sleepDeadline, deadline.timeIntervalSinceNow <= 0 else {
            return false
        }
        sleepDeadline = nil
        sleepArmedMinutes = nil
        if isPlaying {
            pause()
        } else {
            syncTicker()
            emit()
        }
        return true
    }

    /// Called by the store after state changes worth persisting.
    nonisolated static let saveHintInterval: TimeInterval = 5

    private func emit() { onChange?() }
}

extension AudioPlayerEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.syncTicker()
            self.position = self.duration
            self.emit()
        }
    }
}

/// Pure builder for the lock-screen payload so it can be unit-tested without
/// touching MediaPlayer singletons.
enum NowPlaying {
    static func build(
        title: String, author: String, chapter: String?, position: TimeInterval,
        duration: TimeInterval, rate: Double, artwork: UIImage? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: author,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]
        if let chapter {
            info[MPMediaItemPropertyAlbumTitle] = chapter
        }
        // A book with no embedded art still gets a cover: the typographic
        // fallback, rendered by the caller. The lock screen is never blank.
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
        }
        return info
    }
}
