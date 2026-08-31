import AVFoundation
import FluidAudio
import XCTest

@testable import Listnr

/// The only tests that touch the real Parakeet models. They are gated on
/// `LISTNR_ASR_SMOKE=1` because the first run downloads about 1.2 GB of Core ML
/// models — that must never happen inside `scripts/test.sh dev` by accident.
///
/// Enable them by passing the gate as a build setting; the scheme's test action
/// expands it into the test process (see `docs/TESTING.md`):
/// `xcodebuild test … -only-testing:ListnrTests/TranscriberSmokeTests LISTNR_ASR_SMOKE=1`
///
/// The fixture is `speech.m4a`, not `chapters.m4b`: the other fixtures are pure
/// sine tones, and a recogniser has nothing to recognise in a 300 Hz sine.
///
/// Measured on the iPhone 17 Pro simulator (Xcode 26, FluidAudio 0.15.6):
/// see `docs/TESTING.md` for the recorded wall time.
final class TranscriberSmokeTests: XCTestCase {
    static let gate = "LISTNR_ASR_SMOKE"

    private func requireGate() throws {
        guard ProcessInfo.processInfo.environment[Self.gate] == "1" else {
            throw XCTSkip("set \(Self.gate)=1 to run the real Parakeet models (~1.2 GB download)")
        }
    }

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "speech", withExtension: "m4a"),
            "Fixtures/speech.m4a missing — run scripts/make-fixtures.sh")
    }

    /// Loads the models and proves the two things the whole feature rests on:
    /// text, and token timings that rise monotonically inside the duration.
    func testParakeetProducesTextAndTokenTimings() async throws {
        try requireGate()
        let url = try fixtureURL()
        let duration = try await CMTimeGetSeconds(AVURLAsset(url: url).load(.duration))

        let started = Date()
        let models = try await AsrModels.downloadAndLoad(
            configuration: AsrModels.defaultConfiguration())
        let manager = AsrManager(models: models)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(url, decoderState: &state)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertFalse(
            result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Parakeet returned no text after \(elapsed) s")

        let timings = try XCTUnwrap(result.tokenTimings, "no tokenTimings — the feature needs them")
        XCTAssertFalse(timings.isEmpty, "tokenTimings empty — the feature needs them")
        var previous: TimeInterval = -1
        for timing in timings {
            XCTAssertGreaterThanOrEqual(timing.startTime, previous, "token timings went backwards")
            XCTAssertLessThanOrEqual(timing.startTime, duration + 1, "token timing past the file")
            previous = timing.startTime
        }
        XCTAssertFalse(buildWordTimings(from: timings).isEmpty, "no word timings")
    }

    /// Chunking must not move a word in book time. The whole-file run is the
    /// reference; a two-window run has to land the same words within 0.2 s.
    /// If this drifts, fix the offset — never widen the threshold.
    func testChunkedTimestampsMatchTheWholeFileRun() async throws {
        try requireGate()
        let url = try fixtureURL()
        let duration = try await CMTimeGetSeconds(AVURLAsset(url: url).load(.duration))

        let whole = try await words(url: url, duration: duration, window: duration + 1)
        let chunked = try await words(url: url, duration: duration, window: duration / 2)

        XCTAssertGreaterThan(whole.count, 3, "the fixture should yield real words")

        // A word cut on a boundary comes back as two bad tokens. That is the
        // accepted cost of dropping overlap and dedupe — one word per 5 minutes
        // in the app, which the shingle matcher tolerates. What must not move
        // is every other word.
        let reference = uniqueStarts(whole)
        let measured = uniqueStarts(chunked)
        var compared = 0
        for (text, start) in reference {
            guard let other = measured[text] else { continue }
            XCTAssertEqual(other, start, accuracy: 0.2, "chunked timestamp drifted at \(text)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 5, "too few shared words to prove anything")
    }

    /// Words that occur exactly once, so a match is unambiguous.
    private func uniqueStarts(_ words: [TranscriptWord]) -> [String: TimeInterval] {
        var counts: [String: Int] = [:]
        for word in words { counts[word.text, default: 0] += 1 }
        return words.reduce(into: [:]) { out, word in
            if counts[word.text] == 1 { out[word.text] = word.start }
        }
    }

    private func words(
        url: URL, duration: TimeInterval, window: TimeInterval
    ) async throws -> [TranscriptWord] {
        let transcriber = Transcriber(window: window)
        let collected = Collector()
        try await transcriber.transcribe(url: url, duration: duration, from: 0) { words, _ in
            await collected.append(words)
        }
        return await collected.words
    }

    private actor Collector {
        var words: [TranscriptWord] = []
        func append(_ more: [TranscriptWord]) { words.append(contentsOf: more) }
    }
}
