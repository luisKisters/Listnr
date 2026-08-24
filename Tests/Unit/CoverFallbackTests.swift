import SwiftUI
import XCTest
@testable import Listnr

/// The typographic cover fallback: a tone that is the same in every process,
/// a spread across all five tones, and a drawing that actually draws.
@MainActor
final class CoverFallbackTests: XCTestCase {

    // MARK: the tone is stable across runs, not just within one

    /// Hard-coded on purpose: `String.hashValue` is seeded per process, so an
    /// implementation that used it would fail this test on some launch.
    func testToneIsStableAcrossRuns() {
        XCTAssertEqual(Theme.coverToneIndex(for: "Project Hail Mary"), 3)
        XCTAssertEqual(Theme.coverToneIndex(for: "Der Schwarm"), 4)
        XCTAssertEqual(Theme.coverToneIndex(for: "Sea of Tranquility"), 0)
        XCTAssertEqual(Theme.coverToneIndex(for: "The Dawn of Everything"), 1)
        XCTAssertEqual(StableHash.fnv1a(""), 0xcbf2_9ce4_8422_2325)
    }

    func testSameTitleAlwaysSameTone() {
        for title in ["Piranesi", "Dune", "Ulysses", "Der Schwarm"] {
            let first = Theme.coverToneIndex(for: title)
            for _ in 0..<50 {
                XCTAssertEqual(Theme.coverToneIndex(for: title), first)
            }
        }
    }

    func testDifferentTitlesSpreadAcrossAllFiveTones() {
        let buckets = Set((1...40).map { Theme.coverToneIndex(for: "Book \($0)") })
        XCTAssertEqual(buckets, Set(0..<Theme.coverTones.count),
                       "the five tones must all be reachable")
    }

    // MARK: the drawing

    func testFallbackRendersANonEmptyNonUniformSquare() throws {
        let side: CGFloat = 120
        let renderer = ImageRenderer(
            content: CoverView.Fallback(
                title: "The Dawn of Everything",
                author: "Graeber & Wengrow",
                tone: Theme.coverTone(for: "The Dawn of Everything"))
                .frame(width: side, height: side))
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.uiImage, "the fallback must render")
        XCTAssertEqual(image.size.width, side, accuracy: 1)
        XCTAssertEqual(image.size.height, side, accuracy: 1)

        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        XCTAssertGreaterThan(width, 0)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Not blank: something is opaque.
        XCTAssertTrue(pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 },
                      "the rendered cover must not be transparent")

        // Not uniform: type on a gradient means more than one colour.
        var distinct = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let packed = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
            distinct.insert(packed)
            if distinct.count > 8 { break }
        }
        XCTAssertGreaterThan(distinct.count, 8, "a flat square means nothing was drawn on it")
    }

    func testLockScreenArtworkIsRenderedForABookWithoutEmbeddedArt() throws {
        let image = try XCTUnwrap(
            AppModel.renderFallback(title: "Piranesi", author: "Susanna Clarke", side: 240))
        XCTAssertEqual(image.size.width, 240, accuracy: 1)
        XCTAssertEqual(image.size.height, 240, accuracy: 1)
    }
}
