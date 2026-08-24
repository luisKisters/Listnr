import SwiftUI

/// The iOS 26 bottom accessory above the Liquid Glass tab bar: the loaded book
/// in one line, plus the two keys you reach for without looking. It carries no
/// scrubber, no speed and no note key — those belong to the player screen.
///
/// Whether it appears at all is decided by `RootView`, which gates the
/// accessory itself — emptying the content here would still leave the system
/// drawing an empty glass capsule. The system owns the collapse/expand
/// transition; the inline placement simply drops the chapter line and the
/// forward key.
struct MiniPlayerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// The right-rail glyph size and its tap target, as in the player.
    private let glyph: CGFloat = 19
    private let key: CGFloat = 44
    private let thumb: CGFloat = 36

    private var isInline: Bool { placement == .inline }

    var body: some View {
        if let book = model.currentBook, book.hasAudio {
            row(book)
        }
    }

    private func row(_ book: Book) -> some View {
        HStack(spacing: Theme.s3) {
            identity(book)
            playKey
            if !isInline {
                forwardKey
            }
        }
        .padding(.horizontal, Theme.s3)
        .foregroundColor(Theme.ink2)
    }

    /// Everything left of the keys is one control and one accessibility
    /// element: it opens the player. Its own hit shape keeps it clear of the
    /// keys beside it.
    private func identity(_ book: Book) -> some View {
        Button {
            model.tab = .audiobook
        } label: {
            HStack(spacing: Theme.s3) {
                if !isInline {
                    CoverView(book: book, cornerRadius: 8)
                        .frame(width: thumb, height: thumb)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    if !isInline, let chapter = chapterName(book) {
                        Text(chapter)
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now playing: \(book.title)")
        .accessibilityAddTraits(.isButton)
    }

    /// Nil when the book carries no chapters — then the line is omitted.
    private func chapterName(_ book: Book) -> String? {
        book.currentChapter?.title
    }

    private var playKey: some View {
        Button {
            model.togglePlay()
        } label: {
            Image(systemName: model.engine.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: glyph, weight: .medium))
                .frame(width: key, height: key)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.engine.isPlaying ? "Pause" : "Play")
    }

    private var forwardKey: some View {
        Button {
            model.engine.skipForward(30)
        } label: {
            Image(systemName: "goforward.30")
                .font(.system(size: glyph, weight: .medium))
                .frame(width: key, height: key)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Forward 30 seconds")
    }
}
