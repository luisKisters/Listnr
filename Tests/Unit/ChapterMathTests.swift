import XCTest
@testable import Listnr

final class ChapterMathTests: XCTestCase {
    private let duration: TimeInterval = 600
    private let count = 10

    func testIndexAtBoundaries() {
        XCTAssertEqual(ChapterMath.index(at: 0, total: duration, count: count), 0)
        XCTAssertEqual(ChapterMath.index(at: 59, total: duration, count: count), 0)
        XCTAssertEqual(ChapterMath.index(at: 60, total: duration, count: count), 1)
        XCTAssertEqual(ChapterMath.index(at: 599.9, total: duration, count: count), 9)
        // clamping beyond the end
        XCTAssertEqual(ChapterMath.index(at: 99999, total: duration, count: count), 9)
        XCTAssertEqual(ChapterMath.index(at: -5, total: duration, count: count), 0)
    }

    func testDegenerateInputs() {
        XCTAssertEqual(ChapterMath.index(at: 10, total: 0, count: 0), 0)
        XCTAssertNil(ChapterMath.nextChapterStart(position: 0, duration: 100, count: 1))
    }

    func testNextChapterStart() {
        // chapter length here is 60s
        XCTAssertEqual(ChapterMath.nextChapterStart(position: 10, duration: duration, count: count), 60)
        XCTAssertNil(ChapterMath.nextChapterStart(position: 550, duration: duration, count: count))
    }

    func testPreviousRestartsCurrentAfterWindow() {
        // 30s into chapter 2 (starts at 60): past the 4s window -> restart at 60
        XCTAssertEqual(
            ChapterMath.previousChapterStart(position: 90, duration: duration, count: count),
            60)
    }

    func testPreviousJumpsBackWithinWindow() {
        // 2s into chapter 2 -> go to start of chapter 1
        XCTAssertEqual(
            ChapterMath.previousChapterStart(position: 122, duration: duration, count: count),
            60)
    }

    func testPreviousOnFirstChapterNeverNegative() {
        XCTAssertEqual(
            ChapterMath.previousChapterStart(position: 2, duration: duration, count: count),
            0)
    }

    func testSyntheticChaptersEvenSplit() {
        let book = Book(
            id: UUID(), title: "T", author: "A", formats: [.audio],
            duration: duration, position: 0,
            chapterHint: .init(count: 6, word: "Kapitel", names: [2: "Vancouver"]))
        let chapters = book.chapters
        XCTAssertEqual(chapters.count, 6)
        XCTAssertEqual(chapters[0].start, 0)
        XCTAssertEqual(chapters[3].start, 300, accuracy: 0.001)
        XCTAssertEqual(chapters[5].duration, 100, accuracy: 0.001)
        XCTAssertEqual(chapters[0].title, "Kapitel 1")
        XCTAssertEqual(chapters[1].title, "Kapitel 2 — Vancouver")
        XCTAssertEqual(book.currentChapter?.id, 0)

        var moved = book
        moved.position = 350
        XCTAssertEqual(moved.currentChapter?.id, 3)
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
