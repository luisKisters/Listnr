#if DEBUG
import SwiftUI
import UIKit

enum ScanFixture {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-scanfixture")

    static let lead = """
        Am Morgen lag der Nebel noch tief über dem Hafen und die Möwen kreisten \
        lautlos über den nassen Dächern der Stadt.
        """

    static let page = """
        Der Kapitän trat an die Reling und betrachtete das dunkle Wasser unter dem \
        Kiel des Schiffes, denn er wusste, dass die Tiefsee ihre eigenen Gesetze hat \
        und keinem Menschen Rechenschaft schuldig ist.
        """

    static let trail = """
        Später am Abend würde der Sturm kommen, und niemand an Bord konnte ahnen, \
        wie lange die Nacht noch dauern sollte.
        """

    static let firstStart: TimeInterval = 10
    static let wordInterval: TimeInterval = 0.4

    static var truthTime: TimeInterval {
        firstStart + Double(PageMatcher.normalize(lead).count) * wordInterval
    }

    static func transcript(bookID: UUID) -> Transcript {
        let words = PageMatcher.normalize([lead, page, trail].joined(separator: " "))
            .enumerated()
            .map { TranscriptWord(text: $0.element, start: firstStart + Double($0.offset) * wordInterval) }
        return Transcript(bookID: bookID, words: words, language: "de", createdAt: Date())
    }

    static func install(bookID: UUID) {
        Transcript.delete(bookID: bookID)
        try? transcript(bookID: bookID).save()
    }

    @MainActor
    static func pageImage() -> UIImage? {
        let view = Text(AttributedString(page))
            .font(.system(size: 20, weight: .regular, design: .serif))
            .foregroundStyle(Color.black)
            .lineSpacing(10)
            .multilineTextAlignment(.leading)
            .padding(56)
            .frame(width: 720, alignment: .leading)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}
#endif
