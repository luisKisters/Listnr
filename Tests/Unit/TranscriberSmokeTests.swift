import AVFoundation
import XCTest
@testable import Listnr
import FluidAudio

final class TranscriberSmokeTests: XCTestCase {

    private struct ModelDownloadTimedOut: Error {}

    func testParakeetV3TranscribesGermanSpeechWithMonotonicTokenTimings() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "speech", withExtension: "m4b"),
            "Fixtures/speech.m4b missing — run scripts/make-fixtures.sh")
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        let samples = try await Self.decode16kMonoFloat(url: url)
        XCTAssertGreaterThan(samples.count, 16_000, "fixture must hold at least one second of audio")

        let models: AsrModels
        do {
            models = try await Self.downloadModelsWithin(.seconds(240))
        } catch is ModelDownloadTimedOut {
            throw XCTSkip(
                "ASR model (Parakeet v3) not downloaded within 240 s — likely offline or a very "
                    + "slow connection. Skipping loudly instead of hanging or failing.")
        } catch let error as URLError {
            throw XCTSkip(
                "ASR model download needs the network and failed with \(error.code.rawValue) "
                    + "\(error.code). Skipping rather than failing.")
        }

        let manager = AsrManager(config: ASRConfig.default)
        try await manager.loadModels(models)

        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)

        XCTAssertFalse(
            result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "transcription produced no text")
        let timings = try XCTUnwrap(
            result.tokenTimings,
            "tokenTimings is nil — the whole scan feature rests on this field")
        XCTAssertFalse(timings.isEmpty)

        for (a, b) in zip(timings, timings.dropFirst()) {
            XCTAssertTrue(
                b.startTime >= a.startTime - 0.001,
                "token timings not monotonic: '\(a.token)'@\(a.startTime) then '\(b.token)'@\(b.startTime)")
        }
        for timing in timings {
            XCTAssertTrue(timing.startTime >= -0.5, "token starts before the file begins: \(timing)")
            XCTAssertTrue(
                timing.endTime <= duration + 1.0,
                "token ends after the file ends (\(duration) s): \(timing)")
        }
    }

    private static func downloadModelsWithin(_ budget: Duration) async throws -> AsrModels {
        try await withThrowingTaskGroup(of: AsrModels?.self, returning: AsrModels.self) { group in
            group.addTask {
                try await AsrModels.downloadAndLoad(version: .v3)
            }
            group.addTask {
                try await Task.sleep(for: budget)
                return nil
            }
            guard let first = try await group.next(), let models = first else {
                group.cancelAll()
                while (try? await group.next()) != nil {}
                throw ModelDownloadTimedOut()
            }
            group.cancelAll()
            while (try? await group.next()) != nil {}
            return models
        }
    }

    private static func decode16kMonoFloat(url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first, "fixture has no audio track")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw XCTSkip("could not decode fixture audio: \(String(describing: reader.status))")
        }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(
                    blockBuffer, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            data.withUnsafeBytes { raw in
                samples.append(contentsOf: raw.bindMemory(to: Float.self))
            }
        }
        return samples
    }
}
