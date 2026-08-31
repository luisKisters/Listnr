import XCTest
@testable import Listnr

final class PageMatcherTests: XCTestCase {

    private func makeTranscript(_ words: [String]) -> [TranscriptWord] {
        words.enumerated().map { TranscriptWord(text: $0.element, start: Double($0.offset) * 0.5) }
    }

    private func token(_ index: Int) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var n = max(index, 1)
        var out = "w"
        while true {
            out.append(letters[n % 26])
            n /= 26
            if n == 0 { break }
        }
        return out
    }

    func testExactPassageMatchesAtTheRightIndexWithUmlautsAndCaseFolded() throws {
        var vocabulary = (0..<100).map(token)
        vocabulary[42] = "fröhliche"
        vocabulary[43] = "wälder"
        vocabulary[44] = "mädchen"
        let transcript = makeTranscript(vocabulary)
        let passage = (40..<60).map { vocabulary[$0] }.joined(separator: " ").uppercased()

        let match = try XCTUnwrap(PageMatcher.match(ocr: passage, transcript: transcript))

        XCTAssertEqual(match.wordRange.lowerBound, 40)
        XCTAssertEqual(match.time, 20.0, accuracy: 0.001)
        XCTAssertGreaterThan(match.confidence, 0.95)
        XCTAssertTrue(match.snippet.contains("wälder"))
    }

    func testPassageWithTenPercentCorruptedWordsStillMatches() throws {
        let vocabulary = (0..<200).map(token)
        let transcript = makeTranscript(vocabulary)
        let corrupted = (40..<80).enumerated().map { pair in
            pair.offset % 10 == 0 ? "xzqvk\(token(pair.offset))" : vocabulary[pair.offset + 40]
        }
        let passage = corrupted.joined(separator: " ")

        let match = try XCTUnwrap(PageMatcher.match(ocr: passage, transcript: transcript))

        XCTAssertGreaterThanOrEqual(match.wordRange.lowerBound, 40)
        XCTAssertLessThanOrEqual(match.wordRange.lowerBound, 45)
        XCTAssertEqual(
            match.time, Double(match.wordRange.lowerBound) * 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(match.confidence, 0.5)
    }

    func testAPageWhereOnlyAFewShinglesHitReportsNoMatch() {
        let vocabulary = (0..<200).map(token)
        let transcript = makeTranscript(vocabulary)
        let borrowed = (40..<50).map { vocabulary[$0] }
        let foreign = (0..<30).map { "fremd\(token($0))" }

        XCTAssertNil(
            PageMatcher.match(ocr: (borrowed + foreign).joined(separator: " "), transcript: transcript))
    }

    func testPassageFromADifferentBookReportsNoMatch() {
        let transcript = makeTranscript((0..<120).map(token))
        let foreign = "ein völlig fremder text über gartenbau kompostierung und herbstliche blätter"

        XCTAssertNil(PageMatcher.match(ocr: foreign, transcript: transcript))
    }

    func testEmptyOrTwoWordInputReportsNoMatchInsteadOfMatchingAtZero() {
        let transcript = makeTranscript((0..<50).map(token))

        XCTAssertNil(PageMatcher.match(ocr: "", transcript: transcript))
        XCTAssertNil(PageMatcher.match(ocr: "hallo welt", transcript: transcript))
        XCTAssertNil(
            PageMatcher.match(
                ocr: (1...6).map(token).joined(separator: " "),
                transcript: makeTranscript(["a", "b", "c"])))
    }

    func testRepeatedPassageReturnsTheHigherVotedClusterWithLoweredConfidence() throws {
        let fillerA = (0..<90).map { "links\(token($0))" }
        let passage = (0..<30).map { "mitte\(token($0))" }
        let fillerB = (0..<50).map { "rechts\(token($0))" }
        let tail = (0..<8).map { "ende\(token($0))" }
        let words = fillerA + passage + fillerB + passage + tail

        let transcript = makeTranscript(words)
        let ocrWords = passage + Array(tail.prefix(5))
        let secondOccurrence = Double((fillerA.count + passage.count + fillerB.count)) * 0.5

        let match = try XCTUnwrap(PageMatcher.match(ocr: ocrWords.joined(separator: " "), transcript: transcript))

        XCTAssertEqual(match.wordRange.lowerBound, 170)
        XCTAssertEqual(match.time, secondOccurrence, accuracy: 0.001)
        XCTAssertLessThan(match.confidence, 0.9)
    }
}
