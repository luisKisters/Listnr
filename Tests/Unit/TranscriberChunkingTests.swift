import AVFoundation
import XCTest
@testable import Listnr
import FluidAudio

final class TranscriberChunkingTests: XCTestCase {

    private struct ModelDownloadTimedOut: Error {}

    private var bookID = UUID()

    override func setUp() {
        super.setUp()
        bookID = UUID()
        let id = bookID
        addTeardownBlock { Transcript.delete(bookID: id) }
    }

    func testChunkedTranscriptionMatchesWholeFileWithinZeroPointTwoSeconds() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "speech", withExtension: "m4b"),
            "Fixtures/speech.m4b missing — run scripts/make-fixtures.sh")
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let samples = try await Self.decode16kMonoFloat(url: url)

        let models: AsrModels
        do {
            models = try await Self.downloadModelsWithin(.seconds(240))
        } catch is ModelDownloadTimedOut {
            throw XCTSkip(
                "ASR model (Parakeet v3) not downloaded within 240 s — likely offline. "
                    + "Skipping the chunk-equivalence check rather than failing.")
        } catch let error as URLError {
            throw XCTSkip(
                "ASR model download needs the network and failed with \(error.code.rawValue) "
                    + "\(error.code). Skipping rather than failing.")
        }

        let manager = AsrManager(config: ASRConfig.default)
        try await manager.loadModels(models)
        var decoderState = try TdtDecoderState()
        let wholeResult = try await manager.transcribe(samples, decoderState: &decoderState)
        let wholeTimings = try XCTUnwrap(wholeResult.tokenTimings, "tokenTimings is nil")
        let whole = Transcriber.words(from: wholeTimings)
        XCTAssertGreaterThanOrEqual(whole.count, 3, "fixture must transcribe to several words")

        let transcriber = Transcriber(windowSeconds: duration * 0.55, overlapSeconds: 0.4)
        try await transcriber.prepare(models: models)

        let fractions = ProgressCollector()
        let transcript = try await transcriber.transcribe(url: url, bookID: bookID) {
            fractions.append($0)
        }

        XCTAssertFalse(transcript.words.isEmpty)
        XCTAssertEqual(transcript.bookID, bookID)
        let reported = fractions.all
        XCTAssertEqual(reported.last ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(reported, reported.sorted())

        let forward = Self.drift(from: transcript.words, to: whole)
        let backward = Self.drift(from: whole, to: transcript.words)
        XCTAssertLessThanOrEqual(
            forward.drift, 0.2,
            "chunked words drift \(forward.drift)s against whole-file transcription")
        XCTAssertLessThanOrEqual(backward.drift, 0.2)
        XCTAssertLessThanOrEqual(forward.unmatched, 2, "too many chunk-only words")
        XCTAssertLessThanOrEqual(backward.unmatched, 2, "too many whole-file words lost by chunking")

        XCTAssertEqual(Transcript.load(bookID: bookID)?.words, transcript.words)
    }

    func testCancelledTranscriptionLeavesNoTranscriptOnDisk() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "speech", withExtension: "m4b"))
        let transcriber = Transcriber()
        let id = bookID
        let task = Task { try await transcriber.transcribe(url: url, bookID: id) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("transcription should not complete after cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        XCTAssertNil(Transcript.load(bookID: bookID))
    }

    private final class ProgressCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []

        func append(_ value: Double) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var all: [Double] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private static func drift(
        from probe: [TranscriptWord], to reference: [TranscriptWord]
    ) -> (drift: TimeInterval, unmatched: Int) {
        let refs: [(key: String, start: TimeInterval)] = reference.compactMap { word in
            let parts = PageMatcher.normalize(word.text)
            guard !parts.isEmpty else { return nil }
            return (parts.joined(separator: " "), word.start)
        }
        var worst: TimeInterval = 0
        var unmatched = 0
        for word in probe {
            let parts = PageMatcher.normalize(word.text)
            guard !parts.isEmpty else { continue }
            let key = parts.joined(separator: " ")
            var best = TimeInterval.infinity
            for candidate in refs where candidate.key == key {
                best = min(best, abs(candidate.start - word.start))
            }
            if best.isFinite {
                worst = max(worst, best)
            } else {
                unmatched += 1
            }
        }
        return (worst, unmatched)
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
