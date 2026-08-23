import Foundation

/// Chapter math. The mockup model is the contract: chapters divide the book
/// evenly unless real container metadata says otherwise; "previous" restarts
/// the current chapter only in its first four seconds.
enum ChapterMath {
    static let restartWindow: TimeInterval = 4

    /// Evenly divided synthetic chapters, used when a container carries no
    /// chapter metadata. Mirrors mockups/app.js `chapLen` exactly.
    static func syntheticChapters(for book: Book, count: Int) -> [Chapter] {
        guard count > 0 else { return [] }
        let len = book.duration / Double(count)
        return (0..<count).map { i in
            Chapter(
                id: i,
                title: chapterTitle(index: i, count: count, names: [:]),
                start: Double(i) * len,
                duration: len
            )
        }
    }

    /// The display name of one chapter: "Chapter 12 — Rocky" when a name exists.
    static func chapterTitle(index: Int, count: Int, names: [Int: String], word: String = "Chapter") -> String {
        let n = index + 1
        guard n <= max(count, 0) else { return "\(word) \(n)" }
        if let name = names[n], !name.isEmpty {
            return "\(word) \(n) — \(name)"
        }
        return "\(word) \(n)"
    }

    static func index(at position: TimeInterval, total duration: TimeInterval, count: Int) -> Int {
        guard count > 0, duration > 0 else { return 0 }
        let len = duration / Double(count)
        return min(count - 1, max(0, Int(position / len)))
    }

    /// Start time of `index`, clamped into the book.
    static func start(of index: Int, duration: TimeInterval, count: Int) -> TimeInterval {
        guard count > 0, duration > 0 else { return 0 }
        let len = duration / Double(count)
        return min(duration, Double(max(0, index)) * len)
    }

    /// Target position for "previous chapter": inside the first `restartWindow`
    /// seconds of the current chapter it goes to the chapter before, otherwise
    /// it restarts the current one. Returns nil at the very first chapter.
    static func previousChapterStart(
        position: TimeInterval, duration: TimeInterval, count: Int
    ) -> TimeInterval? {
        guard count > 0 else { return nil }
        let i = index(at: position, total: duration, count: count)
        if position - start(of: i, duration: duration, count: count) > restartWindow {
            return start(of: i, duration: duration, count: count)
        }
        guard i > 0 else { return start(of: 0, duration: duration, count: count) }
        return start(of: i - 1, duration: duration, count: count)
    }

    /// Target position for "next chapter"; nil means already at the last one.
    static func nextChapterStart(
        position: TimeInterval, duration: TimeInterval, count: Int
    ) -> TimeInterval? {
        guard count > 0 else { return nil }
        let i = index(at: position, total: duration, count: count)
        guard i + 1 < count else { return nil }
        return start(of: i + 1, duration: duration, count: count)
    }
}
