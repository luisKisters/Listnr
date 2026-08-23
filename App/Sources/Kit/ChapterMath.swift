import Foundation

/// Chapter math over the real chapter boundaries a container declares.
/// Nothing is ever fabricated: an empty chapter list stays empty and every
/// function here answers nil for it. "Previous" restarts the current chapter
/// once more than `restartWindow` seconds into it.
enum ChapterMath {
    static let restartWindow: TimeInterval = 4

    /// Fallback display name for a chapter group the container did not name.
    static func chapterTitle(index: Int) -> String {
        "Chapter \(index + 1)"
    }

    /// Index of the chapter containing `position`, clamped into the list.
    /// Nil when there are no chapters.
    static func index(at position: TimeInterval, in chapters: [Chapter]) -> Int? {
        guard !chapters.isEmpty else { return nil }
        var found = 0
        for (i, chapter) in chapters.enumerated() where position >= chapter.start {
            found = i
        }
        return found
    }

    /// Target position for "previous chapter": more than `restartWindow` into
    /// the current chapter it restarts that chapter, otherwise it goes to the
    /// one before. Never negative, nil when there are no chapters.
    static func previousStart(position: TimeInterval, in chapters: [Chapter]) -> TimeInterval? {
        guard let i = index(at: position, in: chapters) else { return nil }
        let start = chapters[i].start
        if position - start > restartWindow { return max(0, start) }
        guard i > 0 else { return max(0, start) }
        return max(0, chapters[i - 1].start)
    }

    /// Target position for "next chapter"; nil at the last chapter and when
    /// there are no chapters.
    static func nextStart(position: TimeInterval, in chapters: [Chapter]) -> TimeInterval? {
        guard let i = index(at: position, in: chapters) else { return nil }
        guard i + 1 < chapters.count else { return nil }
        return chapters[i + 1].start
    }
}
