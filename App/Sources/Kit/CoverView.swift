import SwiftUI
import UIKit

/// A hash that is the same in every process, on every device, forever.
///
/// `String.hashValue` is seeded per process, so it changes between launches —
/// using it for the cover tone would repaint the library on every start. FNV-1a
/// over the UTF-8 bytes is small, stable and good enough for five buckets.
enum StableHash {
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A stable bucket in `0..<count`.
    static func bucket(_ string: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(fnv1a(string) % UInt64(count))
    }
}

extension Theme {
    /// The cover tone of a title — deterministic, never stored, never random.
    static func coverTone(for title: String) -> Color {
        coverTones[StableHash.bucket(title, count: coverTones.count)]
    }

    static func coverToneIndex(for title: String) -> Int {
        StableHash.bucket(title, count: coverTones.count)
    }
}

/// Loads extracted artwork once and keeps it in memory. Rows redraw often; the
/// disk is not the place to go for that.
@MainActor
enum CoverImageStore {
    private static var cache: [String: UIImage] = [:]

    static func image(named fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        if let hit = cache[fileName] { return hit }
        let url = LibraryIndexer.coversDirectory().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            return nil
        }
        cache[fileName] = image
        return image
    }
}

/// THE cover. Embedded artwork when the container carried some, otherwise the
/// title set in type on one of the five muted tones — never a stock image.
///
/// One view serves every size: 36pt in the mini-player, 64pt in the library,
/// full width in the player. The type scales with the square it is given.
struct CoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 10
    /// Variant B: when set, a progress band rides inside the cover's bottom
    /// edge. `nil` for an unstarted book and for screens that do not want it.
    var progress: Double?

    var body: some View {
        ZStack {
            if let artwork = CoverImageStore.image(named: book.coverFileName) {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Fallback(
                    title: book.title,
                    author: book.author,
                    tone: Theme.coverTone(for: book.title))
            }
        }
        .overlay(alignment: .bottom) {
            if let progress {
                CoverProgressBand(fraction: progress)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.line2, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    /// The drawing itself, free of `Book` so `ImageRenderer` can render it
    /// headlessly for the lock screen and for the tests.
    struct Fallback: View {
        let title: String
        let author: String
        let tone: Color

        var body: some View {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let pad = max(3, side * 0.10)
                let titleSize = max(7, side * 0.125)
                let authorSize = max(5, titleSize * 0.6)
                VStack(alignment: .leading, spacing: max(2, side * 0.035)) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundColor(Theme.ink2)
                        .lineLimit(side < 48 ? 2 : 3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    if !author.isEmpty {
                        Text(author)
                            .font(.system(size: authorSize))
                            .foregroundColor(Theme.ink3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .padding(pad)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .background(
                    LinearGradient(
                        colors: [tone, tone.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            }
        }
    }
}

/// kit.css `.cover .inline-p` — the band that rides inside the cover's own
/// bottom edge: a hairline, a dark plate, and the accent filled from the left.
/// It is always clipped by the cover's corner radius, so it cannot escape.
struct CoverProgressBand: View {
    let fraction: Double

    var body: some View {
        VStack(spacing: 0) {
            Theme.ink3.frame(height: 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.62)
                    Theme.accent
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(height: 4)
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
