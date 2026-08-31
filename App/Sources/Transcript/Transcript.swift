import Foundation

/// One recognised word with the book time it starts at. Two fields on purpose:
/// a 28-hour book is about 300k words, and every extra field is another
/// megabyte on disk and in memory.
struct TranscriptWord: Codable, Sendable, Hashable {
    var text: String
    var start: TimeInterval
}

/// A finished transcript of one book.
struct Transcript: Codable, Sendable, Hashable {
    var bookID: UUID
    var words: [TranscriptWord]
    var language: String?
    var createdAt: Date
}

/// A transcript in progress. The job writes one after every chunk, so a
/// killed job — expiry, low battery, the user cancelling from the system pill
/// — loses at most one chunk. The partial file *is* the feature.
struct TranscriptCheckpoint: Codable, Sendable, Hashable {
    var bookID: UUID
    /// Book time the next chunk starts at.
    var nextOffset: TimeInterval
    var duration: TimeInterval
    var words: [TranscriptWord]

    var fraction: Double {
        duration > 0 ? min(max(nextOffset / duration, 0), 1) : 0
    }
}

/// Transcripts on disk, in the shape `CoverImageStore` uses: an enum of static
/// funcs over `Application Support/Transcripts/`.
///
/// `<bookID>.json` is the finished transcript; `<bookID>.partial.json` is the
/// checkpoint. A book has exactly one of them, never both — `save` deletes the
/// partial as its last act.
enum TranscriptStore {
    /// Overridable so the unit tests write into a temp directory instead of
    /// the real Application Support folder.
    nonisolated(unsafe) static var directoryOverride: URL?

    static func directory() -> URL {
        let dir = directoryOverride ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for bookID: UUID) -> URL {
        directory().appendingPathComponent("\(bookID.uuidString).json")
    }

    static func checkpointURL(for bookID: UUID) -> URL {
        directory().appendingPathComponent("\(bookID.uuidString).partial.json")
    }

    static func exists(bookID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: bookID).path)
    }

    static func load(bookID: UUID) -> Transcript? {
        decode(Transcript.self, from: url(for: bookID))
    }

    static func loadCheckpoint(bookID: UUID) -> TranscriptCheckpoint? {
        decode(TranscriptCheckpoint.self, from: checkpointURL(for: bookID))
    }

    /// Writes the final transcript and drops the checkpoint. Atomic, because a
    /// crash mid-write must not leave a half-parsed transcript that reads as
    /// finished.
    static func save(_ transcript: Transcript) throws {
        try write(transcript, to: url(for: transcript.bookID))
        try? FileManager.default.removeItem(at: checkpointURL(for: transcript.bookID))
    }

    static func saveCheckpoint(_ checkpoint: TranscriptCheckpoint) throws {
        try write(checkpoint, to: checkpointURL(for: checkpoint.bookID))
    }

    static func remove(bookID: UUID) {
        try? FileManager.default.removeItem(at: url(for: bookID))
        try? FileManager.default.removeItem(at: checkpointURL(for: bookID))
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

extension Book {
    /// Never a stored column: the file on disk is the truth, so deleting it
    /// cannot leave the library claiming a transcript that is not there.
    var hasTranscript: Bool { TranscriptStore.exists(bookID: id) }
}
