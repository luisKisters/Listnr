import AVFoundation
import Foundation
import MediaPlayer

/// The real engine: AVAudioPlayer inside an audio-session-configured app with
/// lock-screen controls. All mutable state is main-actor bound; the player's
/// completion callback hops back to the main actor.
@MainActor
final class AudioPlayerEngine: NSObject, PlayerEngine, ObservableObject {
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    /// True while a note sheet holds playback paused.
    var suspendedByNote = false

    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var speed: Double = 1
    @Published private(set) var sleepRemaining: TimeInterval?
    var onChange: (() -> Void)?

    override init() {
        super.init()
        configureAudioSession()
        registerRemoteCommands()
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
        emit()
    }

    func play() {
        guard !isPlaying else { return }
        suspendedByNote = false
        player?.rate = Float(speed)
        player?.play()
        isPlaying = true
        startTicker()
        emit()
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        player?.rate = Float(speed)
        isPlaying = false
        stopTicker()
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
        player?.rate = Float(isPlaying ? speed : speed)
        emit()
    }

    func skipBack(_ interval: TimeInterval) {
        seek(to: position - interval)
    }

    func skipForward(_ interval: TimeInterval) {
        seek(to: position + interval)
    }

    func armSleepTimer(minutes: Int?) {
        guard let minutes, minutes > 0 else {
            sleepRemaining = nil
            emit()
            return
        }
        sleepRemaining = Double(minutes) * 60
        emit()
    }

    func stop() {
        stopTicker()
        player?.stop()
        player = nil
        isPlaying = false
        position = 0
        duration = 0
        sleepRemaining = nil
        emit()
    }

    // MARK: ticking

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
        guard let player else { return }
        position = player.currentTime
        if let sleep = sleepRemaining {
            let step = 0.25 * Double(player.rate)
            let left = sleep - step
            if left <= 0 {
                sleepRemaining = nil
                player.pause()
                isPlaying = false
                stopTicker()
            } else {
                sleepRemaining = left
            }
        }
        emit()
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
            self.stopTicker()
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
        duration: TimeInterval, rate: Double
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
        return info
    }
}
