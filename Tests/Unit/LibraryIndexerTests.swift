import XCTest
@testable import Listnr

/// Two layers:
/// a) `reconcile` as a pure function — no filesystem, no store;
/// b) the real parser against `Fixtures/chapters.m4b`, a file ffmpeg wrote
///    with three named chapters of uneven length.
final class LibraryIndexerTests: XCTestCase {

    // MARK: - helpers

    private func indexed(
        _ path: String, size: Int64, title: String = "T", duration: TimeInterval = 100
    ) -> IndexedBook {
        IndexedBook(
            relativePath: path, fileSize: size, title: title, author: "A", duration: duration)
    }

    private func stored(_ id: UUID, _ path: String, size: Int64) -> StoredBookRef {
        StoredBookRef(id: id, relativePath: path, fileSize: size)
    }

    // MARK: - layer a · pure dedupe

    func testUnchangedPathUpdatesInPlace() {
        let id = UUID()
        let result = LibraryIndexer.reconcile(
            existing: [stored(id, "a.m4b", size: 10)],
            found: [indexed("a.m4b", size: 10, title: "Fresh Title")])

        XCTAssertEqual(result.added.count, 0)
        XCTAssertEqual(result.missing, [])
        XCTAssertEqual(result.updated.count, 1)
        XCTAssertEqual(result.updated[0].id, id)
        XCTAssertFalse(result.updated[0].moved)
        XCTAssertEqual(result.updated[0].book.title, "Fresh Title")
        // The update carries the existing row's id, never a new one.
        XCTAssertEqual(result.updated[0].book.id, id)
    }

    func testMovedFileUpdatesExistingRowAndAddsNothing() {
        let id = UUID()
        // Same bytes, new folder. Duration is deliberately different, to prove
        // it is not part of the identity key (plan amendment 1).
        let result = LibraryIndexer.reconcile(
            existing: [stored(id, "Inbox/schwarm.m4b", size: 4096)],
            found: [indexed("Schätzing/schwarm.m4b", size: 4096, duration: 999)])

        XCTAssertEqual(result.added, [])
        XCTAssertEqual(result.missing, [])
        XCTAssertEqual(result.updated.count, 1)
        XCTAssertEqual(result.updated[0].id, id)
        XCTAssertTrue(result.updated[0].moved)
        XCTAssertEqual(result.updated[0].book.relativePath, "Schätzing/schwarm.m4b")
    }

    func testGenuinelyNewFileIsAdded() {
        let id = UUID()
        let result = LibraryIndexer.reconcile(
            existing: [stored(id, "a.m4b", size: 10)],
            found: [indexed("a.m4b", size: 10), indexed("b.m4b", size: 77, title: "New")])

        XCTAssertEqual(result.updated.count, 1)
        XCTAssertEqual(result.missing, [])
        XCTAssertEqual(result.added.count, 1)
        XCTAssertEqual(result.added[0].title, "New")
    }

    func testVanishedFileIsMarkedMissingNotDeleted() {
        let gone = UUID()
        let kept = UUID()
        let result = LibraryIndexer.reconcile(
            existing: [stored(gone, "gone.m4b", size: 10), stored(kept, "kept.m4b", size: 20)],
            found: [indexed("kept.m4b", size: 20)])

        XCTAssertEqual(result.missing, [gone])
        XCTAssertEqual(result.updated.map(\.id), [kept])
        XCTAssertEqual(result.added, [])
    }

    /// A same-size file must not be stolen by a row whose own path is still
    /// present: path wins over size.
    func testPathMatchWinsOverSizeMatch() {
        let a = UUID()
        let b = UUID()
        let result = LibraryIndexer.reconcile(
            existing: [stored(a, "a.m4b", size: 10), stored(b, "b.m4b", size: 10)],
            found: [indexed("a.m4b", size: 10), indexed("moved/b.m4b", size: 10)])

        XCTAssertEqual(result.added, [])
        XCTAssertEqual(result.missing, [])
        let byID = Dictionary(uniqueKeysWithValues: result.updated.map { ($0.id, $0) })
        XCTAssertEqual(byID[a]?.book.relativePath, "a.m4b")
        XCTAssertEqual(byID[a]?.moved, false)
        XCTAssertEqual(byID[b]?.book.relativePath, "moved/b.m4b")
        XCTAssertEqual(byID[b]?.moved, true)
    }

    /// Two rows of the same size cannot both claim one new path.
    func testOneNewPathIsClaimedOnlyOnce() {
        let a = UUID()
        let b = UUID()
        let result = LibraryIndexer.reconcile(
            existing: [stored(a, "one.m4b", size: 10), stored(b, "two.m4b", size: 10)],
            found: [indexed("moved.m4b", size: 10)])

        XCTAssertEqual(result.updated.count, 1)
        XCTAssertEqual(result.missing.count, 1)
        XCTAssertEqual(result.added, [])
        XCTAssertNotEqual(result.updated[0].id, result.missing[0])
    }

    func testEmptyFolderMarksEverythingMissingAndAddsNothing() {
        let a = UUID()
        let result = LibraryIndexer.reconcile(
            existing: [stored(a, "a.m4b", size: 10)], found: [])
        XCTAssertEqual(result.missing, [a])
        XCTAssertEqual(result.added, [])
        XCTAssertEqual(result.updated, [])
    }

    // MARK: - layer a · what a rescan must not touch

    func testMergePreservesPositionSpeedAndIdentity() {
        let id = UUID()
        let folder = UUID()
        let book = Book(
            id: id, title: "Old", author: "Old Author", formats: [.audio],
            duration: 100, position: 42.5, speed: 1.75,
            chapters: [Chapter(id: 0, title: "Old One", start: 0, duration: 100)],
            sourceFolderID: folder, relativePath: "old.m4b", isMissing: true)

        let fresh = IndexedBook(
            relativePath: "new/place.m4b", fileSize: 99, title: "New", author: "New Author",
            narrator: "Reader", duration: 300,
            chapters: [Chapter(id: 0, title: "Fresh", start: 0, duration: 300)],
            coverFileName: "cover.jpg")

        let merged = LibraryIndexer.merge(fresh, into: book, folderID: folder)

        XCTAssertEqual(merged.position, 42.5)
        XCTAssertEqual(merged.speed, 1.75)
        XCTAssertEqual(merged.id, id)
        XCTAssertEqual(merged.title, "New")
        XCTAssertEqual(merged.narrator, "Reader")
        XCTAssertEqual(merged.duration, 300)
        XCTAssertEqual(merged.relativePath, "new/place.m4b")
        XCTAssertEqual(merged.chapters.first?.title, "Fresh")
        XCTAssertFalse(merged.isMissing)
    }

    /// Position and speed survive a whole reconcile round-trip, not just one
    /// merge: unchanged, moved and vanished rows all keep them.
    func testPositionSurvivesAFullRescanRound() {
        let stay = UUID(), moved = UUID(), gone = UUID()
        var library: [UUID: Book] = [:]
        for (id, path) in [(stay, "stay.m4b"), (moved, "old/moved.m4b"), (gone, "gone.m4b")] {
            library[id] = Book(
                id: id, title: "x", author: "y", formats: [.audio], duration: 10,
                position: 7, speed: 1.5, relativePath: path)
        }
        let existing = [
            stored(stay, "stay.m4b", size: 1),
            stored(moved, "old/moved.m4b", size: 2),
            stored(gone, "gone.m4b", size: 3),
        ]
        let found = [indexed("stay.m4b", size: 1), indexed("new/moved.m4b", size: 2)]
        let result = LibraryIndexer.reconcile(existing: existing, found: found)

        for update in result.updated {
            guard let book = library[update.id] else { return XCTFail("unknown id") }
            library[update.id] = LibraryIndexer.merge(update.book, into: book, folderID: nil)
        }
        for id in result.missing {
            library[id]?.isMissing = true
        }

        XCTAssertEqual(library.count, 3, "no row is ever deleted")
        for (id, book) in library {
            XCTAssertEqual(book.position, 7, "position changed for \(id)")
            XCTAssertEqual(book.speed, 1.5, "speed changed for \(id)")
        }
        XCTAssertEqual(library[gone]?.isMissing, true)
        XCTAssertEqual(library[moved]?.relativePath, "new/moved.m4b")
        XCTAssertEqual(library[stay]?.isMissing, false)
    }

    // MARK: - layer b · the real container

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "chapters", withExtension: "m4b"),
            "Fixtures/chapters.m4b missing — run scripts/make-fixtures.sh")
        return url
    }

    /// A folder holding the m4b, a non-m4b sibling and a hidden file.
    private func makeScanFolder() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("listnr-scan-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: try fixtureURL(), to: nested.appendingPathComponent("chapters.m4b"))
        try Data("not audio".utf8).write(to: root.appendingPathComponent("readme.txt"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden.m4b"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testRealContainerYieldsTitleArtistDurationAndThreeUnevenChapters() async throws {
        let indexer = LibraryIndexer()
        let book = try await indexer.index(
            url: try fixtureURL(), relativePath: "chapters.m4b")

        XCTAssertEqual(book.title, "Der Test Roman")
        XCTAssertEqual(book.author, "Testautor")
        // ffmpeg writes the composer atom; the narrator falls back to it.
        XCTAssertEqual(book.narrator, "Test Sprecher")
        XCTAssertEqual(book.duration, 45, accuracy: 0.2)
        XCTAssertGreaterThan(book.fileSize, 0)

        XCTAssertEqual(book.chapters.count, 3)
        XCTAssertEqual(book.chapters.map(\.title), ["Prolog", "Die Tiefsee", "Kontakt"])
        XCTAssertEqual(book.chapters.map(\.id), [0, 1, 2])

        // Uneven on purpose: 7 / 18 / 20 seconds. An even split would pass a
        // count assertion but fail here.
        XCTAssertEqual(book.chapters[0].start, 0, accuracy: 0.05)
        XCTAssertEqual(book.chapters[0].duration, 7, accuracy: 0.05)
        XCTAssertEqual(book.chapters[1].start, 7, accuracy: 0.05)
        XCTAssertEqual(book.chapters[1].duration, 18, accuracy: 0.05)
        XCTAssertEqual(book.chapters[2].start, 25, accuracy: 0.05)
        XCTAssertEqual(book.chapters[2].duration, 20, accuracy: 0.05)

        // No embedded artwork in the fixture — nil, never a stock image.
        XCTAssertNil(book.coverFileName)
    }

    func testScanKeepsOnlyM4BAndSkipsHiddenFiles() async throws {
        let folder = try makeScanFolder()
        let result = await LibraryIndexer().scan(folder: folder)

        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.books.count, 1)
        XCTAssertEqual(result.books[0].relativePath, "Sub/chapters.m4b")
        XCTAssertEqual(result.books[0].title, "Der Test Roman")
    }

    /// A file that is not really audio must be skipped and counted, not thrown.
    func testBrokenFileIsSkippedAndCounted() async throws {
        let folder = try makeScanFolder()
        try Data("this is not an m4b".utf8)
            .write(to: folder.appendingPathComponent("broken.m4b"))

        let result = await LibraryIndexer().scan(folder: folder)
        XCTAssertEqual(result.books.count, 1)
        XCTAssertEqual(result.skipped, 1)
    }

    /// A rescan of a known path reuses the stored row's id, so the cover file
    /// name stays stable.
    func testScanReusesKnownIDForAKnownPath() async throws {
        let folder = try makeScanFolder()
        let id = UUID()
        let result = await LibraryIndexer().scan(
            folder: folder, knownIDs: ["Sub/chapters.m4b": id])
        XCTAssertEqual(result.books.first?.id, id)
    }

    func testTitleFallsBackToTheFileNameWhenTheContainerHasNone() async throws {
        // alpha.m4a carries no title; index() does not care about the
        // extension, only the enumerator does.
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "alpha", withExtension: "m4a"))
        let book = try await LibraryIndexer().index(url: url, relativePath: "alpha.m4a")
        XCTAssertEqual(book.title, "alpha")
        XCTAssertEqual(book.author, "", "an unlabelled container gets no guessed author")
        XCTAssertEqual(book.chapters, [])
    }
}
