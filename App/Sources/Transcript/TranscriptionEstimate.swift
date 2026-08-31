import Foundation

/// The "about 20 min on this phone" half of the book job's key line.
///
/// Speed is seconds of audio per wall second, measured per chunk and kept in
/// `UserDefaults`. Before any measurement exists the estimate uses 80×, which
/// is the conservative end of what Parakeet on the ANE does. The number is
/// always a real measurement or a stated default — never an animated guess.
enum TranscriptionEstimate {
    static let defaultsKey = "transcribeSpeed"
    static let fallbackSpeed: Double = 80

    /// The measured speed, or the fallback when nothing has been measured yet.
    static func speed(in defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: defaultsKey)
        return stored > 0 ? stored : fallbackSpeed
    }

    /// Keeps the newest measurement. One chunk is enough to replace the
    /// default; later chunks smooth it so a thermal dip does not swing the
    /// estimate wildly.
    static func record(speed: Double, in defaults: UserDefaults = .standard) {
        guard speed > 0, speed.isFinite else { return }
        let previous = defaults.double(forKey: defaultsKey)
        let blended = previous > 0 ? previous * 0.7 + speed * 0.3 : speed
        defaults.set(blended, forKey: defaultsKey)
    }

    /// The book's own length, in the mockup's shape: `27 h 55 min`, `45 min`.
    /// `Fmt.span` writes `27h 55m`, which is the library's row style, not this
    /// screen's — the mockup is the authority here.
    static func duration(_ duration: TimeInterval) -> String {
        let minutes = Int((max(0, duration) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    static func text(duration: TimeInterval, speed: Double) -> String {
        guard duration > 0, speed > 0 else { return "under a minute" }
        let minutes = Int((duration / speed / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "about \(minutes) min" }
        let hours = minutes / 60
        return "about \(hours) h \(minutes % 60) min"
    }
}
