import XCTest
@testable import Listnr

final class ScanStateTests: XCTestCase {

    private func state(
        hasBook: Bool = true,
        selectorOpen: Bool = false,
        hasTranscript: Bool = true,
        preparation: Double? = nil,
        phase: ScanPhase = .idle
    ) -> ScanState {
        ScanLogic.state(
            hasBook: hasBook, selectorOpen: selectorOpen, hasTranscript: hasTranscript,
            preparation: preparation, phase: phase)
    }

    func testNoLoadedAudiobookBeatsEveryOtherState() {
        XCTAssertEqual(state(hasBook: false, selectorOpen: true, hasTranscript: false), .noBook)
    }

    func testTheDrumBeatsPreparationAndThePhase() {
        XCTAssertEqual(
            state(selectorOpen: true, preparation: 0.4, phase: .matched), .selecting)
    }

    func testPreparationBeatsAMissingTranscript() {
        XCTAssertEqual(state(hasTranscript: false, preparation: 0.38), .preparing(0.38))
    }

    func testAMissingTranscriptBeatsTheScanPhase() {
        XCTAssertEqual(state(hasTranscript: false, phase: .reading), .notPrepared)
    }

    func testEveryScanPhaseHasItsOwnState() {
        XCTAssertEqual(state(phase: .idle), .idle)
        XCTAssertEqual(state(phase: .reading), .reading)
        XCTAssertEqual(state(phase: .searching), .searching)
        XCTAssertEqual(state(phase: .matched), .matched)
        XCTAssertEqual(state(phase: .noMatch), .noMatch)
    }

    // MARK: the button

    private func key(
        _ state: ScanState, transcript: Bool = true, camera: Bool = true,
        model: ModelDownload = .ready
    ) -> ScanKey {
        ScanLogic.key(
            for: state, selectionHasTranscript: transcript, cameraReady: camera, model: model)
    }

    func testAddendumA1UntranscribedRowTurnsTheButtonIntoPrepareImmediately() {
        XCTAssertEqual(key(.selecting, transcript: false), .word("Prepare this book"))
    }

    func testAddendumA1TranscribedRowKeepsTheShutterWhileTheDrumIsUp() {
        XCTAssertEqual(key(.selecting, transcript: true), .shutter(enabled: false))
    }

    func testTheShutterIsDisabledWithoutACameraAndWithoutABook() {
        XCTAssertEqual(key(.idle, camera: false), .shutter(enabled: false))
        XCTAssertEqual(key(.noBook), .shutter(enabled: false))
        XCTAssertEqual(key(.idle), .shutter(enabled: true))
    }

    func testWorkingStatesCarryAFractionOnlyWhenThereHonestlyIsOne() {
        XCTAssertEqual(key(.reading), .working(nil))
        XCTAssertEqual(key(.searching), .working(nil))
        XCTAssertEqual(key(.preparing(0.5)), .working(0.5))
    }

    func testTheResultStatesCarryTheirOwnWord() {
        XCTAssertEqual(key(.matched), .word("Jump here"))
        XCTAssertEqual(key(.noMatch), .word("Try again"))
        XCTAssertEqual(key(.notPrepared), .word("Prepare this book"))
    }

    func testEveryStateThatCanBeAbandonedFillsTheCloseSlot() {
        for state in [ScanState.selecting, .matched, .reading, .searching, .preparing(0.1)] {
            XCTAssertTrue(ScanLogic.closes(state), "\(state) must offer a close")
        }
        for state in [ScanState.idle, .noMatch, .notPrepared, .noBook] {
            XCTAssertFalse(ScanLogic.closes(state), "\(state) must not offer a close")
        }
    }

    // MARK: the model comes before the preparation it makes possible

    func testAMissingModelRenamesTheButtonInBothStatesThatOfferPreparing() {
        XCTAssertEqual(key(.notPrepared, model: .missing), .word("Download the model"))
        XCTAssertEqual(
            key(.selecting, transcript: false, model: .missing), .word("Download the model"))
    }

    func testAFailedDownloadStillOffersTheDownload() {
        XCTAssertEqual(key(.notPrepared, model: .failed), .word("Download the model"))
    }

    func testTheRunningDownloadCountsItselfOutOnTheButton() {
        XCTAssertEqual(key(.notPrepared, model: .downloading(0.4)), .working(0.4))
        XCTAssertEqual(
            key(.selecting, transcript: false, model: .downloading(0.4)), .working(0.4))
    }

    func testTheModelNeverTouchesTheStatesThatDoNotAskForIt() {
        XCTAssertEqual(key(.idle, model: .missing), .shutter(enabled: true))
        XCTAssertEqual(key(.matched, model: .missing), .word("Jump here"))
        XCTAssertEqual(key(.preparing(0.5), model: .missing), .working(0.5))
        XCTAssertEqual(key(.selecting, transcript: true, model: .missing), .shutter(enabled: false))
    }

    // MARK: addendum A2 — model detection, stubbed both ways

    func testStubbedModelCacheAnswersBothWays() {
        XCTAssertTrue(AsrModelCache.present.isDownloaded())
        XCTAssertFalse(AsrModelCache.absent.isDownloaded())
    }

    func testTheRealDetectorReportsAnEmptyCacheDirectoryAsMissing() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(AsrModelCache.onDisk(at: directory).isDownloaded())
    }
}

/// The 460 MB model, walked without a network: the cache is the seam, so the
/// whole once-per-install path is a state machine a test can drive.
@MainActor
final class ModelDownloadTests: XCTestCase {

    /// A download that hands back progress and then whatever the caller asked
    /// for. `.stalling` never finishes, so a stop has something to stop.
    private static func cache(
        present: Bool, outcome: @escaping @Sendable () async throws -> Void
    ) -> AsrModelCache {
        AsrModelCache(
            isDownloaded: { present },
            download: { onProgress in
                onProgress(0.4)
                try await outcome()
            })
    }

    private func model(_ cache: AsrModelCache) -> AppModel {
        AppModel(
            store: ListnrStore(inMemory: true, seedSamples: true),
            engine: MockEngine(), modelCache: cache)
    }

    func testAModelAlreadyOnDiskIsReadyAtLaunchAndNeverAsks() {
        XCTAssertEqual(model(.present).modelDownload, .ready)
    }

    func testAMissingModelSaysSoAtLaunch() {
        XCTAssertEqual(model(.absent).modelDownload, .missing)
    }

    func testAReadyModelRefusesToDownloadAgain() {
        let app = model(.present)
        app.downloadModel(then: nil)
        XCTAssertEqual(app.modelDownload, .ready)
    }

    func testTheDownloadRunsToReadyAndLetsTheQueuedBookGo() async {
        let queued = UUID()
        let app = model(Self.cache(present: false, outcome: {}))
        app.downloadModel(then: queued)
        XCTAssertEqual(app.bookWaitingForModel, queued, "the book must wait for the model")
        await until { app.modelDownload == .ready }
        XCTAssertNil(app.bookWaitingForModel, "the wait ends when the model lands")
    }

    func testTheProgressIsTheFractionAndItNeverWalksBackwards() async {
        let app = model(AsrModelCache(
            isDownloaded: { false },
            download: { onProgress in
                onProgress(0.4)
                onProgress(0.1)      // FluidAudio starts the next file over
                try await Task.sleep(nanoseconds: 400_000_000)
            }))
        app.downloadModel(then: nil)
        await until { app.modelDownload == .downloading(0.4) }
        app.stopModelDownload()
    }

    func testAFailedDownloadSaysSoAndPreparesNothing() async {
        struct Offline: Error {}
        let app = model(Self.cache(present: false, outcome: { throw Offline() }))
        app.downloadModel(then: UUID())
        await until { app.modelDownload == .failed }
        XCTAssertNil(app.preparationProgress, "a failed model must not start a preparation")
    }

    func testStoppingGoesBackToMissingBecauseThereIsNoResume() async {
        let app = model(Self.cache(present: false, outcome: {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }))
        app.downloadModel(then: nil)
        await until { app.modelDownload == .downloading(0.4) }
        app.stopModelDownload()
        await until { app.modelDownload == .missing }
    }

    func testPreparingIsRefusedUntilTheModelIsHere() {
        let app = model(.absent)
        guard let book = app.store.books.first(where: { $0.hasAudio }) else {
            return XCTFail("the seeded library must hold an audiobook")
        }
        app.prepareForScanning(bookID: book.id)
        XCTAssertNil(app.preparationProgress, "no model means nothing to prepare with")
    }

    /// Waits for a state the model reaches on its own, without sleeping blind.
    private func until(
        _ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("the model never reached the expected state", file: file, line: line)
    }
}

/// The confirmed jump: step 6. The matched book becomes the loaded one even
/// when the scan was aimed at a different book than the player held.
@MainActor
final class ScanJumpTests: XCTestCase {
    func testJumpAdoptsTheBookSeeksPersistsAndLandsOnTheAudiobookTab() throws {
        let store = ListnrStore(inMemory: true, seedSamples: true)
        let model = AppModel(store: store, engine: MockEngine())
        let target = try XCTUnwrap(
            store.books.first { $0.hasAudio && $0.id != model.currentBookID })

        model.jumpFromScan(bookID: target.id, time: 42)

        XCTAssertEqual(model.currentBookID, target.id, "the scanned book must become the loaded one")
        XCTAssertEqual(model.engine.position, 42, accuracy: 0.1)
        XCTAssertEqual(model.tab, .audiobook)
        XCTAssertEqual(
            store.books.first { $0.id == target.id }?.position ?? -1, 42, accuracy: 0.1,
            "the jump must persist the position")
    }

    func testTheInjectedPageAndTranscriptAgreeOnTheTruthTime() throws {
        let bookID = UUID()
        let transcript = ScanFixture.transcript(bookID: bookID)
        let image = try XCTUnwrap(ScanFixture.pageImage())
        let page = try PageOCR.recognize(image: image)

        let match = try XCTUnwrap(PageMatcher.match(ocr: page.text, transcript: transcript.words))
        XCTAssertEqual(match.time, ScanFixture.truthTime, accuracy: 2)
    }
}
