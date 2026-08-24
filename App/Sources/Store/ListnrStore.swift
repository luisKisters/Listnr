import Foundation
import SwiftData

/// SwiftData records. Plain scalars only — the value types in Kit stay the
/// contract, these are just their row form.
@Model
final class BookRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var narrator: String?
    var hasAudio: Bool
    var hasEbook: Bool
    var fileName: String?
    var duration: Double
    var position: Double
    var speed: Double
    var pageCount: Int
    var page: Int
    var tone: Int
    /// JSON of `[Chapter]` straight from the container. Empty array when the
    /// container declares none.
    var chaptersData: Data = Data()
    var coverFileName: String?
    var sourceFolderID: UUID?
    var relativePath: String?
    var isMissing: Bool = false
    var addedAt: Date

    init(
        id: UUID, title: String, author: String, narrator: String?, hasAudio: Bool,
        hasEbook: Bool, fileName: String?, duration: Double, position: Double, speed: Double,
        pageCount: Int, page: Int, tone: Int, chaptersData: Data = Data(),
        coverFileName: String? = nil, sourceFolderID: UUID? = nil, relativePath: String? = nil,
        isMissing: Bool = false, addedAt: Date
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.narrator = narrator
        self.hasAudio = hasAudio
        self.hasEbook = hasEbook
        self.fileName = fileName
        self.duration = duration
        self.position = position
        self.speed = speed
        self.pageCount = pageCount
        self.page = page
        self.tone = tone
        self.chaptersData = chaptersData
        self.coverFileName = coverFileName
        self.sourceFolderID = sourceFolderID
        self.relativePath = relativePath
        self.isMissing = isMissing
        self.addedAt = addedAt
    }
}

@Model
final class NoteRecord {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var createdAt: Date
    var text: String
    var timestamp: Double

    init(id: UUID, bookID: UUID, createdAt: Date, text: String, timestamp: Double) {
        self.id = id
        self.bookID = bookID
        self.createdAt = createdAt
        self.text = text
        self.timestamp = timestamp
    }
}

/// A folder the user imported, as a row. Every property has a default so
/// adding this model stays a lightweight migration (plan risk 7).
@Model
final class FolderRecord {
    @Attribute(.unique) var id: UUID = UUID()
    /// Security-scoped bookmark data; replaced when it goes stale.
    var bookmark: Data = Data()
    var displayName: String = ""
    var addedAt: Date = Date.distantPast

    init(
        id: UUID = UUID(), bookmark: Data = Data(), displayName: String = "",
        addedAt: Date = Date()
    ) {
        self.id = id
        self.bookmark = bookmark
        self.displayName = displayName
        self.addedAt = addedAt
    }
}

/// The app's single source of truth: the library, the notes, and who was
/// last listened/read. All main-actor; SwiftData context is the main one.
@MainActor
final class ListnrStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var notes: [UUID: [Note]] = [:]
    /// The imported folders, oldest first.
    @Published private(set) var folders: [FolderSource] = []

    let inMemory: Bool
    private var container: ModelContainer?
    private var context: ModelContext?

    /// Which book each resume card points at. Persisted outside SwiftData on
    /// purpose: they survive even a wiped library import.
    private(set) var lastListenedID: UUID?
    private(set) var lastReadID: UUID?

    nonisolated static func audioDirectory() -> URL {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        do {
            let schema = Schema([BookRecord.self, NoteRecord.self, FolderRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container!)
            context!.autosaveEnabled = false
        } catch {
            NSLog("Listnr: store init failed (\(error)); running without persistence")
        }
        loadState()
        if books.isEmpty { seedSampleLibrary() }
    }

    // MARK: persistence of the two pointers

    private var defaults: UserDefaults? {
        inMemory ? nil : .standard
    }

    private func loadState() {
        guard let context else { return }
        let d = defaults
        lastListenedID = d?.uuid(forKey: Keys.lastListened)
        lastReadID = d?.uuid(forKey: Keys.lastRead)

        let bookRows = (try? context.fetch(FetchDescriptor<BookRecord>())) ?? []
        books = bookRows.sorted { $0.addedAt < $1.addedAt }.map(Self.book(from:))

        var map: [UUID: [Note]] = [:]
        let noteRows = (try? context.fetch(
            FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.timestamp)])
        )) ?? []
        for row in noteRows where books.contains(where: { $0.id == row.bookID }) {
            map[row.bookID, default: []].append(Self.note(from: row))
        }
        notes = map

        let folderRows = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
        folders = folderRows.sorted { $0.addedAt < $1.addedAt }.map(Self.folder(from:))
    }

    private enum Keys {
        static let lastListened = "listnr.lastListened"
        static let lastRead = "listnr.lastRead"
    }

    // MARK: record <-> value

    nonisolated static func book(from r: BookRecord) -> Book {
        let chapters = (try? JSONDecoder().decode([Chapter].self, from: r.chaptersData)) ?? []
        var formats = Set<Book.Format>()
        if r.hasAudio { formats.insert(.audio) }
        if r.hasEbook { formats.insert(.ebook) }
        return Book(
            id: r.id, title: r.title, author: r.author, narrator: r.narrator,
            formats: formats,
            audioURL: r.fileName.map { audioDirectory().appendingPathComponent($0) },
            duration: r.duration, position: r.position, speed: r.speed,
            pageCount: r.pageCount, page: r.page, tone: r.tone,
            chapters: chapters, coverFileName: r.coverFileName,
            sourceFolderID: r.sourceFolderID, relativePath: r.relativePath,
            isMissing: r.isMissing
        )
    }

    nonisolated static func folder(from r: FolderRecord) -> FolderSource {
        FolderSource(
            id: r.id, bookmark: r.bookmark, displayName: r.displayName, addedAt: r.addedAt)
    }

    nonisolated static func note(from r: NoteRecord) -> Note {
        Note(id: r.id, bookID: r.bookID, createdAt: r.createdAt, text: r.text, timestamp: r.timestamp)
    }

    // MARK: mutations

    func updatePosition(bookID: UUID, position: TimeInterval, speed: Double) {
        guard let i = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[i].position = position
        books[i].speed = speed
        guard let context else { return }
        let id = bookID
        let fetch = FetchDescriptor<BookRecord>(predicate: #Predicate { $0.id == id })
        if let row = try? context.fetch(fetch).first {
            row.position = position
            row.speed = speed
            try? context.save()
        }
    }

    func markListened(bookID: UUID) {
        lastListenedID = bookID
        defaults?.set(bookID.uuidString, forKey: Keys.lastListened)
    }

    func markRead(bookID: UUID) {
        lastReadID = bookID
        defaults?.set(bookID.uuidString, forKey: Keys.lastRead)
    }

    @discardableResult
    func addNote(bookID: UUID, text: String, timestamp: TimeInterval) -> Note {
        let note = Note(
            id: UUID(), bookID: bookID, createdAt: Date(),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: max(0, timestamp))
        notes[note.bookID, default: []].append(note)
        notes[note.bookID]?.sort { $0.timestamp < $1.timestamp }
        if let context {
            let row = NoteRecord(
                id: note.id, bookID: note.bookID, createdAt: note.createdAt,
                text: note.text, timestamp: note.timestamp)
            context.insert(row)
            try? context.save()
        }
        return note
    }

    func deleteNote(_ note: Note) {
        notes[note.bookID]?.removeAll { $0.id == note.id }
        if let context {
            let id = note.id
            let fetch = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
            if let row = try? context.fetch(fetch).first {
                context.delete(row)
                try? context.save()
            }
        }
    }

    // MARK: folder sources

    /// Adds a folder, or returns the existing one when the same folder is
    /// picked twice — matched by resolved path, since two picks of one folder
    /// produce different bookmark bytes.
    @discardableResult
    func addFolder(_ folder: FolderSource) -> FolderSource {
        if let existing = folders.first(where: { Self.samePath($0, folder) }) { return existing }
        folders.append(folder)
        if let context {
            context.insert(FolderRecord(
                id: folder.id, bookmark: folder.bookmark,
                displayName: folder.displayName, addedAt: folder.addedAt))
            try? context.save()
        }
        return folder
    }

    private nonisolated static func samePath(_ a: FolderSource, _ b: FolderSource) -> Bool {
        guard let lhs = try? a.resolve().url, let rhs = try? b.resolve().url else { return false }
        return lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    func folder(id: UUID) -> FolderSource? {
        folders.first { $0.id == id }
    }

    /// Removes the folder itself. The books that came from it stay — their
    /// notes and positions outlive any import.
    func removeFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        guard let context else { return }
        let target = id
        let fetch = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == target })
        if let row = try? context.fetch(fetch).first {
            context.delete(row)
            try? context.save()
        }
    }

    /// Persists a bookmark that `FolderSource.resolve()` had to re-mint.
    func updateBookmark(folderID: UUID, bookmark: Data) {
        guard let i = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[i].bookmark = bookmark
        guard let context else { return }
        let target = folderID
        let fetch = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == target })
        if let row = try? context.fetch(fetch).first {
            row.bookmark = bookmark
            try? context.save()
        }
    }

    // MARK: sample library

    /// Copies a bundled fixture into the audio directory under `fileName`.
    private func installFixture(named source: String, as fileName: String) -> URL? {
        guard let bundle = Bundle.main.url(forResource: source, withExtension: "m4a") else {
            return nil
        }
        let dest = Self.audioDirectory().appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.copyItem(at: bundle, to: dest)
        }
        return dest
    }

    func seedSampleLibrary() {
        struct Seed {
            var title: String
            var author: String
            var narrator: String?
            var fixture: String?
            var duration: Double
            var position: Double
            var speed: Double
            var ebook: Bool
            var pages: Int
            var page: Int
            var tone: Int
            /// Real chapter boundaries, written out. Uneven on purpose — a
            /// container never hands back a tidy even split.
            var chapters: [Chapter]
        }

        /// Builds a chapter list from (title, length) pairs, so the starts stay
        /// consistent without becoming an even split.
        func chapters(_ spans: [(String, Double)]) -> [Chapter] {
            var start: Double = 0
            var out: [Chapter] = []
            for (i, span) in spans.enumerated() {
                out.append(Chapter(id: i, title: span.0, start: start, duration: span.1))
                start += span.1
            }
            return out
        }

        let seeds: [Seed] = [
            Seed(title: "Project Hail Mary", author: "Andy Weir", narrator: "Ray Porter",
                 fixture: "alpha", duration: 96, position: 40, speed: 1, ebook: false,
                 pages: 476, page: 0, tone: 1,
                 chapters: chapters([
                     ("Chapter 1 — Waking Up", 12), ("Chapter 2", 8), ("Chapter 3", 10),
                     ("Chapter 4", 14), ("Chapter 5", 8), ("Chapter 6 — Astrophage", 14),
                     ("Chapter 7", 14), ("Chapter 8", 16),
                 ])),
            Seed(title: "Der Schwarm", author: "Frank Schätzing", narrator: "Frank Glaubrecht",
                 fixture: "bravo", duration: 120, position: 8, speed: 1.2, ebook: false,
                 pages: 1000, page: 0, tone: 2,
                 chapters: chapters([
                     ("Prolog", 6), ("Huanchaco, Peru", 11), ("Vancouver Island", 15),
                     ("Trondheim", 9), ("Kiel", 13), ("Der Kontinentalhang", 18),
                     ("Die Tiefsee", 12), ("Chateaneuf", 7), ("Independence", 16),
                     ("Kontakt", 13),
                 ])),
            Seed(title: "The Dawn of Everything", author: "Graeber & Wengrow",
                 narrator: "Mark Williams", fixture: "charlie", duration: 72, position: 0,
                 speed: 1, ebook: false, pages: 704, page: 0, tone: 3,
                 chapters: chapters([
                     ("Farewell to Humanity’s Childhood", 9), ("Wicked Liberty", 17),
                     ("Unfreezing the Ice Age", 13), ("Free People", 21),
                     ("Many Seasons Ago", 12),
                 ])),
            Seed(title: "Piranesi", author: "Susanna Clarke", narrator: "Chiwetel Ejiofor",
                 fixture: "bravo", duration: 120, position: 45, speed: 1.5, ebook: true,
                 pages: 272, page: 60, tone: 4,
                 chapters: chapters([
                     ("Piranesi", 14), ("The Other", 9), ("The Drowned Halls", 22),
                     ("The Labyrinth", 11), ("The Prophet", 18), ("Valentine Ketterley", 13),
                     ("Matthew Rose Sorensen", 16), ("Wave", 7), ("The Beauty of the House", 10),
                 ])),
            Seed(title: "Sea of Tranquility", author: "Emily St. John Mandel", narrator: nil,
                 fixture: nil, duration: 0, position: 0, speed: 1, ebook: true,
                 pages: 272, page: 148, tone: 5, chapters: []),
        ]

        var seeded: [Book] = []
        for s in seeds {
            let id = UUID()
            var url: URL?
            if let fixture = s.fixture {
                url = installFixture(named: fixture, as: "\(id.uuidString).m4a")
            }
            let chaptersData = (try? JSONEncoder().encode(s.chapters)) ?? Data()
            var formats = Set<Book.Format>()
            if url != nil { formats.insert(.audio) }
            if s.ebook { formats.insert(.ebook) }
            let book = Book(
                id: id, title: s.title, author: s.author, narrator: s.narrator,
                formats: formats,
                audioURL: url, duration: s.duration, position: s.position, speed: s.speed,
                pageCount: s.pages, page: s.page, tone: s.tone,
                chapters: url != nil ? s.chapters : [])
            seeded.append(book)

            if let context {
                context.insert(BookRecord(
                    id: id, title: s.title, author: s.author, narrator: s.narrator,
                    hasAudio: url != nil, hasEbook: s.ebook,
                    fileName: url?.lastPathComponent, duration: s.duration,
                    position: s.position, speed: s.speed, pageCount: s.pages,
                    page: s.page, tone: s.tone,
                    chaptersData: url != nil ? chaptersData : Data(),
                    addedAt: Date()))
            }
        }
        try? context?.save()

        books = seeded
        notes = [:]
        lastListenedID = seeded.first(where: { $0.title == "Project Hail Mary" })?.id
        lastReadID = seeded.first(where: { $0.title == "Sea of Tranquility" })?.id
        if !inMemory {
            defaults?.set(lastListenedID?.uuidString, forKey: Keys.lastListened)
            defaults?.set(lastReadID?.uuidString, forKey: Keys.lastRead)
        }
    }
}

extension UserDefaults {
    func uuid(forKey key: String) -> UUID? {
        guard let s = string(forKey: key) else { return nil }
        return UUID(uuidString: s)
    }
}
