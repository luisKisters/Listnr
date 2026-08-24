import AVFoundation
import Foundation
import UIKit

/// One audio file as the container describes it. A pure value type: the
/// indexer never sees SwiftData and never sees a view.
struct IndexedBook: Sendable, Hashable, Identifiable {
    /// The id the book will get when it is added, and the name of its cover
    /// file. A rescan of a known path reuses the existing row's id.
    var id: UUID
    /// Path inside the source folder, e.g. `Schätzing/Der Schwarm.m4b`.
    /// This is the identity key (plan amendment 1).
    var relativePath: String
    var fileSize: Int64
    var title: String
    var author: String
    var narrator: String?
    var duration: TimeInterval
    /// Exactly what the container declares. Never fabricated, never split.
    var chapters: [Chapter]
    /// File name inside `Application Support/Covers`, nil when the container
    /// carries no artwork — the typographic fallback is the view's job.
    var coverFileName: String?

    init(
        id: UUID = UUID(), relativePath: String, fileSize: Int64, title: String,
        author: String, narrator: String? = nil, duration: TimeInterval = 0,
        chapters: [Chapter] = [], coverFileName: String? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.title = title
        self.author = author
        self.narrator = narrator
        self.duration = duration
        self.chapters = chapters
        self.coverFileName = coverFileName
    }
}

/// The result of walking one folder.
struct ScanResult: Sendable {
    var books: [IndexedBook] = []
    /// Files that looked like audiobooks but could not be parsed. A broken
    /// file never aborts a scan.
    var skipped: Int = 0
}

/// The subset of a stored row that identity matching needs. Keeping it this
/// small is what makes `reconcile` a pure function you can test without a
/// filesystem or a store.
struct StoredBookRef: Sendable, Hashable {
    var id: UUID
    var relativePath: String
    var fileSize: Int64

    init(id: UUID, relativePath: String, fileSize: Int64) {
        self.id = id
        self.relativePath = relativePath
        self.fileSize = fileSize
    }
}

/// What a rescan decided. `missing` carries ids, never rows to delete: a book
/// whose file vanished keeps its notes and its position.
struct Reconciliation: Sendable, Equatable {
    struct Update: Sendable, Equatable {
        var id: UUID
        var book: IndexedBook
        /// True when the file was found under a different path than the stored
        /// one — it moved inside the folder.
        var moved: Bool
    }

    var updated: [Update] = []
    var added: [IndexedBook] = []
    var missing: [UUID] = []
}

/// Walks a folder, reads every `.m4b` with the async AVFoundation loaders, and
/// hands back value types. An actor so a scan of a 500-file library never runs
/// on the main actor.
actor LibraryIndexer {
    enum IndexError: Error {
        case unreadable
        case noDuration
    }

    // MARK: - dedupe (pure)

    /// Matches stored rows against what the folder now contains.
    ///
    /// Identity is `relativePath` first. A row whose path is gone is matched to
    /// an unclaimed new path by `fileSize` — that is the "moved inside the
    /// folder" case, and it updates the row instead of adding a second one.
    /// Only a row with no match at all is reported missing.
    ///
    /// `duration` is deliberately not part of the key: it would force a full
    /// `AVAsset` load of every file on every rescan (plan amendment 1).
    ///
    /// Pure: no filesystem, no store, no clock.
    nonisolated static func reconcile(
        existing: [StoredBookRef], found: [IndexedBook]
    ) -> Reconciliation {
        var result = Reconciliation()
        var claimed = Set<Int>()

        // Pass 1 — same path. Duplicate paths cannot happen inside one folder,
        // but a first-match lookup keeps the function total if they do.
        var byPath: [String: Int] = [:]
        for (i, book) in found.enumerated() where byPath[book.relativePath] == nil {
            byPath[book.relativePath] = i
        }

        var unmatched: [StoredBookRef] = []
        for row in existing {
            if let i = byPath[row.relativePath], !claimed.contains(i) {
                claimed.insert(i)
                var book = found[i]
                book.id = row.id
                result.updated.append(.init(id: row.id, book: book, moved: false))
            } else {
                unmatched.append(row)
            }
        }

        // Pass 2 — same size at a new path: the file moved.
        var bySize: [Int64: [Int]] = [:]
        for (i, book) in found.enumerated() where !claimed.contains(i) {
            bySize[book.fileSize, default: []].append(i)
        }
        for row in unmatched {
            guard var candidates = bySize[row.fileSize],
                  let i = candidates.first(where: { !claimed.contains($0) })
            else {
                result.missing.append(row.id)
                continue
            }
            claimed.insert(i)
            candidates.removeAll { $0 == i }
            bySize[row.fileSize] = candidates
            var book = found[i]
            book.id = row.id
            result.updated.append(.init(id: row.id, book: book, moved: true))
        }

        for (i, book) in found.enumerated() where !claimed.contains(i) {
            result.added.append(book)
        }
        return result
    }

    /// Folds an indexed file into an existing row. Everything the user made —
    /// `position`, `speed`, the id, and the notes hanging off that id — is
    /// untouched by construction.
    nonisolated static func merge(_ indexed: IndexedBook, into book: Book, folderID: UUID?) -> Book {
        var out = book
        out.title = indexed.title
        out.author = indexed.author
        out.narrator = indexed.narrator
        out.duration = indexed.duration
        out.chapters = indexed.chapters
        out.coverFileName = indexed.coverFileName ?? book.coverFileName
        out.relativePath = indexed.relativePath
        out.sourceFolderID = folderID ?? book.sourceFolderID
        out.isMissing = false
        out.formats.insert(.audio)
        return out
    }

    // MARK: - covers

    nonisolated static func coversDirectory() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - scanning

    /// Every `.m4b` under `folder`, recursively, hidden files skipped.
    /// Sorted by path so a scan is deterministic.
    nonisolated static func audioFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var out: [URL] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "m4b" {
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Path of `url` relative to `folder`, with no leading slash.
    nonisolated static func relativePath(of url: URL, in folder: URL) -> String {
        let base = folder.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(base) else { return url.lastPathComponent }
        var rest = String(full.dropFirst(base.count))
        while rest.hasPrefix("/") { rest.removeFirst() }
        return rest.isEmpty ? url.lastPathComponent : rest
    }

    /// Walks the folder and reads every file. A file that fails to parse is
    /// skipped and counted; it never aborts the scan.
    ///
    /// `knownIDs` maps a relative path to the id of the row that already holds
    /// it, so a rescan writes its cover back to the same `<bookID>.jpg`.
    func scan(folder: URL, knownIDs: [String: UUID] = [:]) async -> ScanResult {
        var result = ScanResult()
        for url in Self.audioFiles(in: folder) {
            let path = Self.relativePath(of: url, in: folder)
            do {
                let book = try await index(url: url, relativePath: path, id: knownIDs[path])
                result.books.append(book)
            } catch {
                result.skipped += 1
            }
        }
        return result
    }

    /// Reads one container. Async loaders only — the synchronous `AVAsset`
    /// properties are deprecated and block.
    func index(url: URL, relativePath: String, id: UUID? = nil) async throws -> IndexedBook {
        let bookID = id ?? UUID()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let asset = AVURLAsset(url: url)

        let cmDuration = try await asset.load(.duration)
        guard cmDuration.isNumeric else { throw IndexError.noDuration }
        let duration = CMTimeGetSeconds(cmDuration)
        guard duration.isFinite, duration > 0 else { throw IndexError.noDuration }

        let common = try await asset.load(.commonMetadata)
        let fileTitle = url.deletingPathExtension().lastPathComponent
        let title = await string(from: common, key: .commonKeyTitle) ?? fileTitle
        // No guessed author: an unlabelled container stays empty.
        let author = await string(from: common, key: .commonKeyArtist) ?? ""
        let narrator = try await narrator(of: asset)
        let chapters = try await chapters(of: asset)
        let cover = await writeCover(from: common, bookID: bookID)

        return IndexedBook(
            id: bookID, relativePath: relativePath, fileSize: size, title: title,
            author: author, narrator: narrator, duration: duration,
            chapters: chapters, coverFileName: cover)
    }

    // MARK: - metadata helpers

    /// Actor-isolated on purpose: `AVMetadataItem` is a reference type, so
    /// letting an array of them cross an isolation boundary is a data race.
    private func string(from items: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        for item in items where item.commonKey == key {
            if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
        }
        return nil
    }

    /// `©nrt` in the iTunes space, composer (`©wrt`) as the fallback, nil when
    /// the container names nobody. Never a guess.
    private func narrator(of asset: AVURLAsset) async throws -> String? {
        let items = try await asset.loadMetadata(for: .iTunesMetadata)
        if let narrator = await iTunesValue(items, identifierSuffix: "%A9nrt") { return narrator }
        return await iTunesValue(items, identifierSuffix: "%A9wrt")
    }

    /// iTunes atoms come back with a numeric key, so the four-character code is
    /// matched on the identifier instead (`itsk/%A9nrt`).
    private func iTunesValue(
        _ items: [AVMetadataItem], identifierSuffix suffix: String
    ) async -> String? {
        let needle = suffix.lowercased()
        for item in items {
            let raw = item.identifier?.rawValue.lowercased() ?? ""
            guard raw.hasSuffix(needle) else { continue }
            if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
        }
        return nil
    }

    /// The container's chapters, or an empty list.
    ///
    /// Plan risk 6, and it bites in practice: `withTitleLocale:` returns
    /// nothing unless the locale matches the chapter text track's language,
    /// and real m4b files routinely tag that track `und`. So: the current
    /// locale, then the user's preferred languages, then every locale the file
    /// actually declares — only after all three is a file chapterless.
    private func chapters(of asset: AVURLAsset) async throws -> [Chapter] {
        let keys: [AVMetadataKey] = [.commonKeyTitle]
        var groups = try await asset.loadChapterMetadataGroups(
            withTitleLocale: .current, containingItemsWithCommonKeys: keys)
        if groups.isEmpty {
            groups = try await asset.loadChapterMetadataGroups(
                bestMatchingPreferredLanguages: Locale.preferredLanguages)
        }
        if groups.isEmpty {
            for locale in try await asset.load(.availableChapterLocales) {
                groups = try await asset.loadChapterMetadataGroups(
                    withTitleLocale: locale, containingItemsWithCommonKeys: keys)
                if !groups.isEmpty { break }
            }
        }

        var chapters: [Chapter] = []
        for (i, group) in groups.enumerated() {
            let range = group.timeRange
            guard range.start.isNumeric, range.duration.isNumeric else { continue }
            let name = await string(from: group.items, key: .commonKeyTitle)
            chapters.append(Chapter(
                id: chapters.count,
                title: name ?? ChapterMath.chapterTitle(index: i),
                start: CMTimeGetSeconds(range.start),
                duration: CMTimeGetSeconds(range.duration)))
        }
        return chapters
    }

    /// Writes embedded artwork to `Application Support/Covers/<bookID>.jpg`.
    /// Returns nil when the container has none — no stock image, ever.
    private func writeCover(from items: [AVMetadataItem], bookID: UUID) async -> String? {
        var raw: Data?
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                raw = data
                break
            }
        }
        guard let raw, let image = UIImage(data: raw),
              let jpeg = image.jpegData(compressionQuality: 0.85)
        else { return nil }
        let name = "\(bookID.uuidString).jpg"
        let dest = Self.coversDirectory().appendingPathComponent(name)
        do {
            try jpeg.write(to: dest, options: .atomic)
        } catch {
            return nil
        }
        return name
    }
}
