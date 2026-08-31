import AVFoundation
import FluidAudio
import Foundation

/// The seam between the job and Parakeet. Two implementations: `Transcriber`
/// here, and `FakeTranscriber` in the test target — the controller in
/// `TranscriptionJob` is untestable against a 1.2 GB model, exactly as the
/// `-mockengine` precedent.
protocol Transcribing: Sendable {
    /// True when the speech models are already on this phone.
    var modelsReady: Bool { get }

    /// Fetches the speech models. `onProgress` gets a real fraction of the
    /// download, never an animated one.
    func downloadModels(onProgress: @Sendable @escaping (Double) -> Void) async throws

    /// Transcribes `url` from `offset` to the end, calling `onChunk` after
    /// every finished window. The caller owns the checkpoint; this never
    /// writes anything.
    func transcribe(
        url: URL,
        duration: TimeInterval,
        from offset: TimeInterval,
        onChunk: @Sendable ([TranscriptWord], _ nextOffset: TimeInterval) async -> Void
    ) async throws
}

enum TranscriberError: LocalizedError {
    case noAudioTrack
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "This file has no audio track."
        case .decodeFailed: return "This audio could not be decoded."
        }
    }
}

/// FluidAudio Parakeet v3, on the Neural Engine, one 5-minute window at a time.
///
/// Windows do not overlap. A word cut on a boundary is one bad token per 300 s,
/// which the scan matcher tolerates and which removes dedupe logic entirely.
actor Transcriber: Transcribing {
    /// 5 minutes. Long enough that model overhead is noise, short enough that
    /// the system progress pill moves every 10–30 s on a phone.
    static let windowLength: TimeInterval = 300

    /// Parakeet needs 300 ms of 16 kHz audio; a shorter tail is silence.
    private static let minimumSamples = 4_800

    /// Overridable only so the smoke test can compare a chunked run against a
    /// whole-file run on a 6-second fixture. The app always uses the default.
    private let window: TimeInterval
    private var manager: AsrManager?

    init(window: TimeInterval = Transcriber.windowLength) {
        self.window = window
    }

    // MARK: chunk math — pure, so it is tested without audio or a model

    static func windows(
        duration: TimeInterval, from offset: TimeInterval, window: TimeInterval = windowLength
    ) -> [ClosedRange<TimeInterval>] {
        guard duration > 0, window > 0 else { return [] }
        var start = max(0, offset)
        var out: [ClosedRange<TimeInterval>] = []
        while start < duration {
            out.append(start...min(start + window, duration))
            start += window
        }
        return out
    }

    // MARK: models

    /// FluidAudio keeps the compiled models in
    /// `Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3`.
    private static var modelDirectory: URL { AsrModels.defaultCacheDirectory(for: .v3) }

    nonisolated var modelsReady: Bool { AsrModels.modelsExist(at: Self.modelDirectory) }

    func downloadModels(onProgress: @Sendable @escaping (Double) -> Void) async throws {
        // Loading is the download plus the Core ML compile, and the reported
        // fraction already covers both halves.
        manager = try await load(onProgress: onProgress)
    }

    /// `defaultConfiguration()` is already `.cpuAndNeuralEngine`. That is not a
    /// preference: a continued-processing task may not touch the GPU without an
    /// entitlement we do not have, and the ANE is available while locked.
    private func load(onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> AsrManager {
        if let manager { return manager }
        var handler: ProgressHandler?
        if let onProgress {
            handler = { progress in onProgress(progress.fractionCompleted) }
        }
        let models = try await AsrModels.downloadAndLoad(
            configuration: AsrModels.defaultConfiguration(),
            version: .v3,
            progressHandler: handler)
        let fresh = AsrManager(models: models)
        manager = fresh
        return fresh
    }

    // MARK: transcription

    func transcribe(
        url: URL,
        duration: TimeInterval,
        from offset: TimeInterval,
        onChunk: @Sendable ([TranscriptWord], _ nextOffset: TimeInterval) async -> Void
    ) async throws {
        let windows = Self.windows(duration: duration, from: offset, window: window)
        guard !windows.isEmpty else { return }
        let manager = try await load()

        for window in windows {
            if Task.isCancelled { return }
            let chunk = try await Self.samples(url: url, in: window)
            var words: [TranscriptWord] = []
            if chunk.samples.count >= Self.minimumSamples {
                var state = TdtDecoderState.make(
                    decoderLayers: await manager.decoderLayerCount)
                let result = try await manager.transcribe(chunk.samples, decoderState: &state)
                // Every timing is relative to the chunk, so the chunk's real
                // start is added back before anything leaves this actor.
                words = buildWordTimings(from: result.tokenTimings ?? []).map {
                    TranscriptWord(text: $0.word, start: chunk.start + $0.startTime)
                }
            }
            if Task.isCancelled { return }
            await onChunk(words, window.upperBound)
        }
    }

    // MARK: audio

    /// One window of the container decoded to what Parakeet wants: 16 kHz mono
    /// Float32. Mono makes interleaved and non-interleaved the same bytes, so
    /// the flag is left at the value every decoder accepts.
    ///
    /// `start` is the presentation time of the first sample actually returned,
    /// not the requested window start: `AVAssetReader` snaps a time range to
    /// packet boundaries, and assuming the requested value moved every word in
    /// a resumed chunk about 0.3 s early (measured against a whole-file run).
    private static func samples(
        url: URL, in window: ClosedRange<TimeInterval>
    ) async throws -> (samples: [Float], start: TimeInterval) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriberError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: window.lowerBound, preferredTimescale: 600),
            duration: CMTime(
                seconds: window.upperBound - window.lowerBound, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        guard reader.canAdd(output) else { throw TranscriberError.decodeFailed }
        reader.add(output)
        guard reader.startReading() else { throw TranscriberError.decodeFailed }

        var samples: [Float] = []
        var start = window.lowerBound
        var sawFirst = false
        while let buffer = output.copyNextSampleBuffer() {
            if !sawFirst {
                let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                if pts.isValid { start = CMTimeGetSeconds(pts) }
                sawFirst = true
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: length)
            guard CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: length, destination: &bytes) == noErr
            else { throw TranscriberError.decodeFailed }
            bytes.withUnsafeBytes { raw in
                samples.append(contentsOf: raw.bindMemory(to: Float.self))
            }
        }
        if reader.status == .failed { throw TranscriberError.decodeFailed }
        return (samples, start)
    }
}

/// The deterministic stand-in, next to the protocol like `MockEngine` sits
/// next to `PlayerEngine`. The controller in `TranscriptionJob` cannot be
/// tested against a 1.2 GB model, and neither can a UI test or a screenshot.
///
/// Emits a fixed number of words per window, and can be told to fail or to
/// take its time so a cancel has something to cancel.
final class FakeTranscriber: Transcribing {
    let modelsReady: Bool
    let wordsPerChunk: Int
    /// Throws on the window with this index, when set.
    let failOnChunk: Int?
    let chunkDelay: Duration
    let downloadSteps: Int
    /// Shorter than the real 300 s so a short sample book still produces many
    /// chunks — the running state has to be observable in a UI test and in a
    /// screenshot.
    let window: TimeInterval

    init(
        modelsReady: Bool = true, wordsPerChunk: Int = 3, failOnChunk: Int? = nil,
        chunkDelay: Duration = .zero, downloadSteps: Int = 4,
        window: TimeInterval = Transcriber.windowLength
    ) {
        self.modelsReady = modelsReady
        self.wordsPerChunk = wordsPerChunk
        self.failOnChunk = failOnChunk
        self.chunkDelay = chunkDelay
        self.downloadSteps = downloadSteps
        self.window = window
    }

    func downloadModels(onProgress: @Sendable @escaping (Double) -> Void) async throws {
        for step in 1...downloadSteps {
            try await Task.sleep(for: .milliseconds(120))
            onProgress(Double(step) / Double(downloadSteps))
        }
    }

    func transcribe(
        url: URL,
        duration: TimeInterval,
        from offset: TimeInterval,
        onChunk: @Sendable ([TranscriptWord], _ nextOffset: TimeInterval) async -> Void
    ) async throws {
        let windows = Transcriber.windows(duration: duration, from: offset, window: self.window)
        for (index, window) in windows.enumerated() {
            if chunkDelay > .zero { try await Task.sleep(for: chunkDelay) }
            if Task.isCancelled { return }
            if index == failOnChunk { throw TranscriberError.decodeFailed }
            let words = (0..<wordsPerChunk).map { i in
                TranscriptWord(
                    text: "w\(Int(window.lowerBound))-\(i)",
                    start: window.lowerBound + Double(i))
            }
            await onChunk(words, window.upperBound)
        }
    }
}
