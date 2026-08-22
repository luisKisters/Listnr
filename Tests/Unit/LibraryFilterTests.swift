import XCTest
@testable import Listnr

final class LibraryFilterTests: XCTestCase {
    private func book(
        _ title: String, formats: Set<Book.Format>, duration: TimeInterval = 100,
        position: TimeInterval = 0, page: Int = 0, pageCount: Int = 0
    ) -> Book {
        Book(
            id: UUID(), title: title, author: "An Author", formats: formats,
            duration: duration, position: position,
            pageCount: pageCount, page: page)
    }

    private var library: [Book] {
        [
            book("Alpha", formats: [.audio], position: 50),                       // in progress
            book("Bravo", formats: [.audio]),                                     // new
            book("Charlie", formats: [.ebook], page: 80, pageCount: 100),         // in progress
            book("Delta", formats: [.audio, .ebook], position: 10),               // paired
            book("Echo", formats: [.audio], duration: 300, position: 300),         // finished
        ]
    }

    func testAllIncludesEverything() {
        XCTAssertEqual(LibraryQuery.books(from: library, filter: .all, sort: .title, query: "").count, 5)
    }

    func testAudiobooksExcludesEbookOnly() {
        let result = LibraryQuery.books(from: library, filter: .audiobooks, sort: .title, query: "")
        XCTAssertEqual(result.map(\.title), ["Alpha", "Bravo", "Delta", "Echo"])
    }

    func testEbooksIncludesPaired() {
        let result = LibraryQuery.books(from: library, filter: .ebooks, sort: .title, query: "")
        XCTAssertEqual(result.map(\.title), ["Charlie", "Delta"])
    }

    func testPairedOnly() {
        let result = LibraryQuery.books(from: library, filter: .paired, sort: .title, query: "")
        XCTAssertEqual(result.map(\.title), ["Delta"])
    }

    func testInProgressExcludesNewAndFinished() {
        let result = LibraryQuery.books(from: library, filter: .inProgress, sort: .title, query: "")
        XCTAssertEqual(result.map(\.title), ["Alpha", "Charlie", "Delta"])
    }

    func testSearchMatchesTitleOrAuthorCaseInsensitive() {
        XCTAssertEqual(
            LibraryQuery.books(from: library, filter: .all, sort: .title, query: "  alph ").map(\.title),
            ["Alpha"])
        // every fixture shares author "An Author"
        XCTAssertEqual(
            LibraryQuery.books(from: library, filter: .all, sort: .title, query: "an au").count, 5)
    }

    func testSortByTitleAndLength() {
        let byTitle = LibraryQuery.books(from: library, filter: .all, sort: .title, query: "")
        XCTAssertEqual(byTitle.first?.title, "Alpha")
        let byLength = LibraryQuery.sorted(library, by: .length)
        XCTAssertEqual(byLength.map(\.title).first, "Echo")   // longest duration
    }

    func testRecentRankPinsResumeBooks() {
        // built inline so the pinned IDs belong to this exact array
        let books = [
            book("Alpha", formats: [.audio], position: 50),
            book("Bravo", formats: [.audio]),
            book("Charlie", formats: [.ebook], page: 80, pageCount: 100),
        ]
        let result = LibraryQuery.sorted(
            books, by: .recent, recentIDs: [books[2].id, books[0].id])
        XCTAssertEqual(result.prefix(2).map(\.title), ["Charlie", "Alpha"])
    }
}
