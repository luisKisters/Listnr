import Foundation

struct TranscriptWord: Codable, Hashable, Sendable {
    let text: String
    let start: TimeInterval
}

struct Transcript: Codable, Hashable, Sendable {
    let bookID: UUID
    let words: [TranscriptWord]
    let language: String?
    let createdAt: Date
}

extension Transcript {
    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for bookID: UUID) -> URL {
        directory().appendingPathComponent("\(bookID.uuidString).json")
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.url(for: bookID), options: .atomic)
    }

    static func load(bookID: UUID) -> Transcript? {
        guard let data = try? Data(contentsOf: url(for: bookID)) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    static func delete(bookID: UUID) {
        try? FileManager.default.removeItem(at: url(for: bookID))
        TranscriptCheckpoint.delete(bookID: bookID)
    }
}

/// Where a stopped preparation continues. Written after every full window,
/// deleted by the final `Transcriber.write`; "stop" is "pause".
struct TranscriptCheckpoint: Codable, Hashable, Sendable {
    let bookID: UUID
    let nextOffset: TimeInterval
    let duration: TimeInterval
    let words: [TranscriptWord]
}

extension TranscriptCheckpoint {
    static func url(for bookID: UUID) -> URL {
        Transcript.directory().appendingPathComponent("\(bookID.uuidString).partial.json")
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.url(for: bookID), options: .atomic)
    }

    static func load(bookID: UUID) -> TranscriptCheckpoint? {
        guard let data = try? Data(contentsOf: url(for: bookID)) else { return nil }
        return try? JSONDecoder().decode(TranscriptCheckpoint.self, from: data)
    }

    static func delete(bookID: UUID) {
        try? FileManager.default.removeItem(at: url(for: bookID))
    }
}

extension Book {
    var hasTranscript: Bool {
        FileManager.default.fileExists(atPath: Transcript.url(for: id).path)
    }
}
