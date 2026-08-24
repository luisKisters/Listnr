import XCTest
@testable import Listnr

final class ChapterMathTests: XCTestCase {
    /// Deliberately uneven: an even split would not tell the boundary code from
    /// the old count-based math. Starts: 0, 30, 100, 130, 260. End: 300.
    private let chapters: [Chapter] = [
        Chapter(id: 0, title: "One", start: 0, duration: 30),
        Chapter(id: 1, title: "Two", start: 30, duration: 70),
        Chapter(id: 2, title: "Three", start: 100, duration: 30),
        Chapter(id: 3, title: "Four", start: 130, duration: 130),
        Chapter(id: 4, title: "Five", start: 260, duration: 40),
    ]

    private let none: [Chapter] = []

    // MARK: index

    func testIndexInsideAndAtBoundaries() {
        XCTAssertEqual(ChapterMath.index(at: 0, in: chapters), 0)
        XCTAssertEqual(ChapterMath.index(at: 29.9, in: chapters), 0)
        XCTAssertEqual(ChapterMath.index(at: 30, in: chapters), 1)
        XCTAssertEqual(ChapterMath.index(at: 99.9, in: chapters), 1)
        XCTAssertEqual(ChapterMath.index(at: 100, in: chapters), 2)
        XCTAssertEqual(ChapterMath.index(at: 200, in: chapters), 3)
        XCTAssertEqual(ChapterMath.index(at: 260, in: chapters), 4)
    }

    func testIndexClampsOutsideTheBook() {
        XCTAssertEqual(ChapterMath.index(at: -50, in: chapters), 0)
        XCTAssertEqual(ChapterMath.index(at: 99_999, in: chapters), 4)
    }

    // MARK: next

    func testNextStartUsesTheRealBoundary() {
        XCTAssertEqual(ChapterMath.nextStart(position: 10, in: chapters), 30)
        XCTAssertEqual(ChapterMath.nextStart(position: 99, in: chapters), 100)
        XCTAssertEqual(ChapterMath.nextStart(position: 200, in: chapters), 260)
    }

    func testNextStartIsNilAtTheLastChapter() {
        XCTAssertNil(ChapterMath.nextStart(position: 260, in: chapters))
        XCTAssertNil(ChapterMath.nextStart(position: 299, in: chapters))
    }

    // MARK: previous

    func testPreviousRestartsTheCurrentChapterPastTheWindow() {
        // 35 s into chapter four (starts at 130) — well past the 4 s window,
        // so "previous" restarts chapter four itself.
        XCTAssertEqual(ChapterMath.previousStart(position: 165, in: chapters), 130)
        // Exactly at the window edge still counts as "still at the start".
        XCTAssertEqual(ChapterMath.previousStart(position: 134, in: chapters), 100)
        XCTAssertEqual(ChapterMath.previousStart(position: 134.01, in: chapters), 130)
    }

    func testPreviousStepsBackInsideTheWindow() {
        // 2 s into chapter four -> the start of chapter three.
        XCTAssertEqual(ChapterMath.previousStart(position: 132, in: chapters), 100)
        // 1 s into chapter two -> the start of chapter one.
        XCTAssertEqual(ChapterMath.previousStart(position: 31, in: chapters), 0)
    }

    func testPreviousOnTheFirstChapterNeverGoesNegative() {
        XCTAssertEqual(ChapterMath.previousStart(position: 2, in: chapters), 0)
        XCTAssertEqual(ChapterMath.previousStart(position: 0, in: chapters), 0)
        XCTAssertEqual(ChapterMath.previousStart(position: 20, in: chapters), 0)
    }

    // MARK: the empty list — the whole "no synthetic splits" rule

    func testEveryFunctionIsNilForAnEmptyChapterList() {
        XCTAssertNil(ChapterMath.index(at: 0, in: none))
        XCTAssertNil(ChapterMath.index(at: 500, in: none))
        XCTAssertNil(ChapterMath.previousStart(position: 0, in: none))
        XCTAssertNil(ChapterMath.previousStart(position: 500, in: none))
        XCTAssertNil(ChapterMath.nextStart(position: 0, in: none))
        XCTAssertNil(ChapterMath.nextStart(position: 500, in: none))
    }

    func testChapterTitleFallsBackToChapterN() {
        XCTAssertEqual(ChapterMath.chapterTitle(index: 0), "Chapter 1")
        XCTAssertEqual(ChapterMath.chapterTitle(index: 11), "Chapter 12")
    }

    // MARK: Book

    func testCurrentChapterFollowsThePosition() {
        var book = Book(
            id: UUID(), title: "T", author: "A", formats: [.audio],
            duration: 300, position: 0, chapters: chapters)
        XCTAssertEqual(book.currentChapter?.title, "One")
        book.position = 150
        XCTAssertEqual(book.currentChapter?.title, "Four")
    }

    func testBookWithoutChaptersHasNoCurrentChapter() {
        let book = Book(
            id: UUID(), title: "T", author: "A", formats: [.audio],
            duration: 300, position: 150)
        XCTAssertTrue(book.chapters.isEmpty)
        XCTAssertNil(book.currentChapter)
    }

    func testFormatWordAndPaired() {
        let audioOnly = Book(id: UUID(), title: "A", author: "B", formats: [.audio])
        let paired = Book(id: UUID(), title: "P", author: "C", formats: [.audio, .ebook])
        let ebookOnly = Book(id: UUID(), title: "E", author: "D", formats: [.ebook])
        XCTAssertTrue(audioOnly.formatWord == "Audiobook")
        XCTAssertTrue(paired.isPaired && paired.formatWord == "Ebook and audiobook")
        XCTAssertTrue(ebookOnly.formatWord == "Ebook" && !ebookOnly.isPaired)
    }

    func testProgressClamps() {
        var book = Book(
            id: UUID(), title: "T", author: "A", formats: [.audio], duration: 100)
        XCTAssertEqual(book.progressPercent, 0)
        book.position = 50
        XCTAssertEqual(book.progressPercent, 50)
        book.position = 500
        XCTAssertEqual(book.progressPercent, 100)
        book.position = -10
        XCTAssertEqual(book.progressPercent, 0)
    }
}
