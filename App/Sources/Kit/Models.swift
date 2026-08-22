import Foundation

/// Where a book's chapters come from when the container has no metadata:
/// an even split with display metadata.
struct ChapterHint: Hashable, Sendable {
    var count: Int
    var word: String
    var names: [Int: String]
}

/// One book in any mix of formats. A paired title carries both formats and one
/// shared position — the position lives on the audio side when audio exists.
struct Book: Identifiable, Hashable, Sendable {
    enum Format: String, Sendable, CaseIterable {
        case audio
        case ebook
    }

    let id: UUID
    var title: String
    var author: String
    var narrator: String?
    var formats: Set<Format>
    /// Absolute file URL of the audio container, when the book has one.
    var audioURL: URL?
    var duration: TimeInterval
    /// Shared playback position in seconds. For paired titles this is THE position.
    var position: TimeInterval
    var speed: Double
    /// Page state for ebook-only titles (reader arrives post-V0).
    var pageCount: Int
    var page: Int
    /// Index into the five muted cover tones of the design system.
    var tone: Int
    var chapterHint: ChapterHint?

    init(
        id: UUID, title: String, author: String, narrator: String? = nil,
        formats: Set<Format>, audioURL: URL? = nil, duration: TimeInterval = 0,
        position: TimeInterval = 0, speed: Double = 1, pageCount: Int = 0, page: Int = 0,
        tone: Int = 1, chapterHint: ChapterHint? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.narrator = narrator
        self.formats = formats
        self.audioURL = audioURL
        self.duration = duration
        self.position = position
        self.speed = speed
        self.pageCount = pageCount
        self.page = page
        self.tone = tone
        self.chapterHint = chapterHint
    }

    var hasAudio: Bool { formats.contains(.audio) }
    var hasEbook: Bool { formats.contains(.ebook) }
    var isPaired: Bool { formats.count > 1 }

    var chapterCount: Int { chapterHint?.count ?? 0 }

    /// The chapter list this book plays with: even split plus display names.
    var chapters: [Chapter] {
        guard hasAudio else { return [] }
        let hint = chapterHint ?? ChapterHint(count: max(1, Int(duration / 600)), word: "Chapter", names: [:])
        return ChapterMath.syntheticChapters(for: self, count: hint.count).map { ch in
            Chapter(
                id: ch.id,
                title: ChapterMath.chapterTitle(index: ch.id, count: hint.count, names: hint.names, word: hint.word),
                start: ch.start, duration: ch.duration)
        }
    }

    var currentChapter: Chapter? {
        let list = chapters
        guard !list.isEmpty else { return nil }
        return list[ChapterMath.index(at: position, total: duration, count: list.count)]
    }

    var progress: Double {
        if hasAudio {
            return duration > 0 ? min(max(position / duration, 0), 1) : 0
        }
        return pageCount > 0 ? min(max(Double(page) / Double(pageCount), 0), 1) : 0
    }

    var progressPercent: Int { Int((progress * 100).rounded()) }

    var remaining: TimeInterval { max(0, duration - position) }

    var formatWord: String {
        if isPaired { return "Ebook and audiobook" }
        return hasAudio ? "Audiobook" : "Ebook"
    }
}

/// One chapter of an audiobook.
struct Chapter: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var start: TimeInterval
    var duration: TimeInterval

    var end: TimeInterval { start + duration }
}

/// A timestamped note. Saving one pauses playback and resumes afterwards.
struct Note: Identifiable, Hashable, Sendable {
    let id: UUID
    var bookID: UUID
    var createdAt: Date
    var text: String
    /// Book time in seconds the note is anchored to.
    var timestamp: TimeInterval
}
