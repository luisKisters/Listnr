import AVFoundation
import Foundation
import FluidAudio

actor Transcriber {
    enum TranscriberError: Error {
        case unreadable
    }

    private let manager = AsrManager(config: ASRConfig.default)
    private let windowSeconds: TimeInterval
    private let overlapSeconds: TimeInterval

    init(windowSeconds: TimeInterval = 600, overlapSeconds: TimeInterval = 4) {
        self.windowSeconds = max(windowSeconds, 1)
        self.overlapSeconds = min(max(overlapSeconds, 0), windowSeconds / 2)
    }

    /// The 460 MB download, once per install. The progress is FluidAudio's own
    /// fraction, handed on untouched — whoever shows it decides what to do
    /// with it.
    static func loadModels(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> AsrModels {
        try await AsrModels.downloadAndLoad(version: .v3) { progress in
            onProgress(progress.fractionCompleted)
        }
    }

    func prepare(models: AsrModels) async throws {
        try await manager.loadModels(models)
    }

    func transcribe(
        url: URL,
        bookID: UUID,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Transcript {
        try Task.checkCancellation()
        let sampleRate = 16_000
        let asset = AVURLAsset(url: url)
        let cmDuration = try await asset.load(.duration)
        guard cmDuration.isNumeric else { throw TranscriberError.unreadable }
        let duration = CMTimeGetSeconds(cmDuration)
        guard duration.isFinite, duration > 0 else { throw TranscriberError.unreadable }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw TranscriberError.unreadable }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        guard reader.startReading() else { throw TranscriberError.unreadable }

        let strideSamples = max(1, Int(windowSeconds * Double(sampleRate)))
        let overlapSamples = min(Int(overlapSeconds * Double(sampleRate)), strideSamples / 2)
        let overlapTime = TimeInterval(overlapSamples) / Double(sampleRate)

        var words: [TranscriptWord] = []
        var buffer: [Float] = []
        var windowStart: TimeInterval = 0
        var firstWindow = true

        while case let sampleBuffer? = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(
                    blockBuffer, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            data.withUnsafeBytes { raw in
                buffer.append(contentsOf: raw.bindMemory(to: Float.self))
            }
            while buffer.count >= strideSamples {
                words.append(contentsOf: try await transcribeChunk(
                    Array(buffer[..<strideSamples]), windowStart: windowStart,
                    overlapTime: firstWindow ? 0 : overlapTime))
                firstWindow = false
                buffer.removeFirst(strideSamples - overlapSamples)
                windowStart += Double(strideSamples - overlapSamples) / Double(sampleRate)
                onProgress(min(windowStart, duration) / duration)
            }
        }
        guard reader.status == .completed || reader.status == .cancelled else {
            throw TranscriberError.unreadable
        }
        if !buffer.isEmpty {
            words.append(contentsOf: try await transcribeChunk(
                buffer, windowStart: windowStart,
                overlapTime: firstWindow ? 0 : overlapTime))
        }
        onProgress(1)

        let transcript = Transcript(bookID: bookID, words: words, language: nil, createdAt: Date())
        try Task.checkCancellation()
        try Self.write(transcript)
        return transcript
    }

    private func transcribeChunk(
        _ samples: [Float], windowStart: TimeInterval, overlapTime: TimeInterval
    ) async throws -> [TranscriptWord] {
        try Task.checkCancellation()
        // Each window is decoded on its own: the overlap, not the decoder
        // state, is what carries a word across the seam.
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        guard let timings = result.tokenTimings else { return [] }
        return Self.words(
            from: timings, offset: windowStart,
            dropBefore: windowStart + overlapTime - 0.001)
    }

    nonisolated static func write(_ transcript: Transcript) throws {
        let data = try JSONEncoder().encode(transcript)
        let dir = Transcript.directory()
        let temp = dir.appendingPathComponent("\(transcript.bookID.uuidString).tmp.json")
        let target = Transcript.url(for: transcript.bookID)
        do {
            try data.write(to: temp, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: temp, to: target)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    nonisolated static func words(
        from timings: [TokenTiming],
        offset: TimeInterval = 0,
        dropBefore: TimeInterval = -.infinity
    ) -> [TranscriptWord] {
        var words: [TranscriptWord] = []
        var swallowing = false
        for timing in timings {
            let raw = timing.token
            let text = raw.drop(while: { $0 == " " || $0 == "▁" })
            let startsWord = text.startIndex != raw.startIndex || words.isEmpty
            if !startsWord {
                if !swallowing, let last = words.last {
                    words[words.count - 1] = TranscriptWord(
                        text: last.text + raw, start: last.start)
                }
                continue
            }
            guard !text.isEmpty else { continue }
            let absolute = offset + timing.startTime
            if absolute < dropBefore {
                swallowing = true
                continue
            }
            swallowing = false
            words.append(TranscriptWord(text: String(text), start: absolute))
        }
        return words
    }
}
