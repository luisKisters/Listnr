import Foundation

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
    /// The real chapters read from the audio container. Empty when the
    /// container declares none — the list is never fabricated.
    var chapters: [Chapter]
    /// File name of the extracted cover art inside `Application Support/Covers`.
    var coverFileName: String?
    /// The imported folder this book came from, when it was imported.
    var sourceFolderID: UUID?
    /// Path of the audio file relative to its source folder.
    var relativePath: String?
    /// True when the file vanished from its source folder. Rows are never
    /// deleted — notes and position survive.
    var isMissing: Bool

    init(
        id: UUID, title: String, author: String, narrator: String? = nil,
        formats: Set<Format>, audioURL: URL? = nil, duration: TimeInterval = 0,
        position: TimeInterval = 0, speed: Double = 1, pageCount: Int = 0, page: Int = 0,
        chapters: [Chapter] = [], coverFileName: String? = nil,
        sourceFolderID: UUID? = nil, relativePath: String? = nil, isMissing: Bool = false
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
        self.chapters = chapters
        self.coverFileName = coverFileName
        self.sourceFolderID = sourceFolderID
        self.relativePath = relativePath
        self.isMissing = isMissing
    }

    var hasAudio: Bool { formats.contains(.audio) }
    var hasEbook: Bool { formats.contains(.ebook) }
    var isPaired: Bool { formats.count > 1 }

    /// The chapter `position` falls into; nil when the book has no chapters.
    var currentChapter: Chapter? {
        guard let i = ChapterMath.index(at: position, in: chapters) else { return nil }
        return chapters[i]
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

/// One chapter of an audiobook, exactly as the container declares it.
struct Chapter: Identifiable, Hashable, Sendable, Codable {
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
