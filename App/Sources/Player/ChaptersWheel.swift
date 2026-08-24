import SwiftUI

/// The chapter wheel — the iOS time-picker drum (SwiftUI `Picker` with
/// `.pickerStyle(.wheel)` is the native component). Settling on a row seeks
/// the engine; the selection haptic fires per detent. There is no public API
/// for the UIPickerView tick sound, so we do not fake one.
///
/// It floats inside the cover's square, over the blurred artwork, and takes
/// whatever frame the caller gives it. The rows carry their own ink so a
/// near-white cover underneath cannot wash the titles out; the caller's scrim
/// does the rest. No `Done` button — the wheel commits when it settles.
struct ChaptersWheelView: View {
    let book: Book
    let position: TimeInterval
    let onSelect: (Chapter) -> Void

    @State private var selection: Chapter.ID?
    /// Cancelled by every new detent; the survivor is the settled choice.
    @State private var commit: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Chapters", selection: Binding(
                get: { selection ?? currentIndex },
                set: { newValue in
                    selection = newValue
                    UISelectionFeedbackGenerator().selectionChanged()
                    commitWhenSettled(newValue)
                })) {
                ForEach(book.chapters) { chapter in
                    Text(chapter.title)
                        .font(.system(size: Theme.tLG, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .tag(Optional(chapter.id))
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Theme.s4)
        .onAppear { selection = currentIndex }
    }

    /// The wheel commits on settle: every detent restarts a short timer and
    /// only the value the wheel comes to rest on reaches the engine. That is
    /// why there is no Done button — it would be a second way to do one thing.
    private func commitWhenSettled(_ id: Chapter.ID?) {
        commit?.cancel()
        commit = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let id,
                  let chapter = book.chapters.first(where: { $0.id == id })
            else { return }
            onSelect(chapter)
        }
    }

    private var currentIndex: Chapter.ID? {
        guard let i = ChapterMath.index(at: position, in: book.chapters) else { return nil }
        return book.chapters[i].id
    }
}
