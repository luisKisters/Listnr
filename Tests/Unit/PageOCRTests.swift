import SwiftUI
import UIKit
import XCTest
@testable import Listnr

@MainActor
final class PageOCRTests: XCTestCase {

    private let passage = """
        Als Gregor Samsa eines Morgens aus unruhigen Träumen erwachte, fand er sich in seinem \
        Bett zu einem ungeheueren Ungeziefer verwandelt. Er lag auf seinem panzerartig harten \
        Rücken und sah, wenn er den Kopf ein wenig hob, seinen gewölbten, braunen, von \
        bogenförmigen Versteifungen geteilten Bauch, auf dessen Höhe sich die Bettdecke, zum \
        gänzlichen Niedergleiten bereit, kaum noch erhalten konnte. Seine vielen, im Vergleich \
        zu seinem sonstigen Umfang kläglich dünnen Beine flimmerten ihm hilflos vor den Augen. \
        Was ist mit mir geschehen, dachte er. Es war kein Traum. Sein Zimmer, ein richtiges, \
        nur etwas zu kleines Menschenzimmer, lag ruhig zwischen den vier wohlbekannten Wänden, \
        und über dem Tisch lagen die ausgepackten Stoffmuster bereit.
        """

    func testRenderedGermanPageIsReadAboveWordThreshold() throws {
        let image = try XCTUnwrap(renderPage(passage))
        let page = try PageOCR.recognize(image: image)

        XCTAssertFalse(page.text.isEmpty)
        XCTAssertGreaterThan(page.meanConfidence, 0.5)
        XCTAssertGreaterThan(wordMatchRate(source: passage, ocr: page.text), 0.9)
    }

    func testRecognizedPageDrivesTheMatcherToTheRightPosition() throws {
        let transcript = PageMatcher.normalize(passage).enumerated().map {
            TranscriptWord(text: $0.element, start: Double($0.offset) * 0.5)
        }
        let image = try XCTUnwrap(renderPage(passage))
        let page = try PageOCR.recognize(image: image)

        let match = try XCTUnwrap(PageMatcher.match(ocr: page.text, transcript: transcript))

        XCTAssertEqual(match.wordRange.lowerBound, 0)
        XCTAssertGreaterThan(match.confidence, 0.5)
    }

    private func renderPage(_ text: String) -> UIImage? {
        let view = Text(AttributedString(text))
            .font(.system(size: 20, weight: .regular, design: .serif))
            .lineSpacing(10)
            .multilineTextAlignment(.leading)
            .padding(56)
            .frame(width: 720, alignment: .leading)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    private func wordMatchRate(source: String, ocr: String) -> Double {
        let expected = PageMatcher.normalize(source)
        guard !expected.isEmpty else { return 0 }
        var recovered = PageMatcher.normalize(ocr)
        var hits = 0
        for word in expected {
            if let index = recovered.firstIndex(of: word) {
                recovered.remove(at: index)
                hits += 1
            }
        }
        return Double(hits) / Double(expected.count)
    }
}
