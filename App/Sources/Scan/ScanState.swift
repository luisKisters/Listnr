import Foundation

enum ScanPhase: Equatable {
    case idle
    case reading
    case searching
    case matched
    case noMatch
}

enum ScanState: Equatable {
    case noBook
    case selecting
    case preparing(Double)
    case notPrepared
    case reading
    case searching
    case matched
    case noMatch
    case idle
}

/// The 460 MB speech model on this device. It belongs to the app, not to the
/// Scan view: a view-local task dies with the sheet, with the tab switch and
/// with the lock screen, and FluidAudio cannot resume — a killed download
/// starts again at zero.
enum ModelDownload: Equatable {
    case missing
    case downloading(Double)
    case failed
    case ready
}

enum ScanKey: Equatable {
    case shutter(enabled: Bool)
    case working(Double?)
    case word(String)
}

enum ScanLogic {
    static func state(
        hasBook: Bool,
        selectorOpen: Bool,
        hasTranscript: Bool,
        preparation: Double?,
        phase: ScanPhase
    ) -> ScanState {
        guard hasBook else { return .noBook }
        if selectorOpen { return .selecting }
        if let preparation { return .preparing(preparation) }
        guard hasTranscript else { return .notPrepared }
        switch phase {
        case .idle: return .idle
        case .reading: return .reading
        case .searching: return .searching
        case .matched: return .matched
        case .noMatch: return .noMatch
        }
    }

    /// `model` is the speech model on this device. A book that cannot be
    /// prepared until a 460 MB download lands must not offer "Prepare this
    /// book": the button names the real first step instead.
    static func key(
        for state: ScanState,
        selectionHasTranscript: Bool,
        cameraReady: Bool,
        model: ModelDownload = .ready
    ) -> ScanKey {
        switch state {
        case .noBook:
            return .shutter(enabled: false)
        case .selecting:
            return selectionHasTranscript
                ? .shutter(enabled: false)
                : (modelKey(model) ?? .word("Prepare this book"))
        case .preparing(let fraction):
            return .working(fraction)
        case .notPrepared:
            return modelKey(model) ?? .word("Prepare this book")
        case .reading, .searching:
            return .working(nil)
        case .matched:
            return .word("Jump here")
        case .noMatch:
            return .word("Try again")
        case .idle:
            return .shutter(enabled: cameraReady)
        }
    }

    private static func modelKey(_ model: ModelDownload) -> ScanKey? {
        switch model {
        case .ready: return nil
        case .downloading(let fraction): return .working(fraction)
        case .missing, .failed: return .word("Download the model")
        }
    }

    static func closes(_ state: ScanState) -> Bool {
        switch state {
        case .selecting, .preparing, .reading, .searching, .matched: return true
        case .noBook, .notPrepared, .noMatch, .idle: return false
        }
    }
}
