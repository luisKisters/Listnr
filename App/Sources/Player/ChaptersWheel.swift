import SwiftUI

/// The chapter wheel — the iOS time-picker drum (SwiftUI `Picker` with
/// `.pickerStyle(.wheel)` is the native component). Settling on a row seeks
/// the engine; the selection haptic fires per detent. There is no public API
/// for the UIPickerView tick sound, so we do not fake one.
struct ChaptersWheelView: View {
    let book: Book
    let position: TimeInterval
    let onSelect: (Chapter) -> Void

    @State private var selection: Chapter.ID?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Chapters", selection: Binding(
                get: { selection ?? currentIndex },
                set: { newValue in
                    selection = newValue
                    UISelectionFeedbackGenerator().selectionChanged()
                })) {
                ForEach(book.chapters) { chapter in
                    Text(chapter.title).tag(Optional(chapter.id))
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.inset)
        .overlay(alignment: .bottomTrailing) {
            Button {
                if let id = selection ?? currentIndex,
                   let chapter = book.chapters.first(where: { $0.id == id }) {
                    onSelect(chapter)
                }
            } label: {
                Text("Done")
                    .font(.system(size: Theme.tSM, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(14)
            .accessibilityLabel("Done picking chapters")
        }
        .onAppear { selection = currentIndex }
    }

    private var currentIndex: Chapter.ID? {
        guard let i = ChapterMath.index(at: position, in: book.chapters) else { return nil }
        return book.chapters[i].id
    }
}
