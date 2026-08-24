import SwiftUI

/// Timestamped note capture. Playback is already paused by the time this sheet
/// appears; saving or dismissing resumes it when it was playing before.
struct NoteSheetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            editor
                .padding(.top, Theme.s4)
            actions
                .padding(.top, Theme.s4)
            if !previous.isEmpty {
                Rectangle()
                    .fill(Theme.line2)
                    .frame(height: 1)
                    .padding(.top, Theme.s5)
                previousNotes
                    .padding(.top, Theme.s5)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.inset)
        .padding(.top, Theme.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raise)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    /// Left: why the clock stands still, and where the note lands.
    /// Right: the chapter that timestamp falls in.
    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
            Image(systemName: "pause.fill")
                .font(.system(size: 11))
                .foregroundColor(Theme.ink3)
            Text(Fmt.hms(model.engine.position))
                .font(.system(size: Theme.tSM, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.ink)
            Spacer(minLength: Theme.s3)
            Text(chapterName)
                .font(.system(size: Theme.tXS))
                .foregroundColor(Theme.ink3)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// No box: the caret is the only affordance.
    private var editor: some View {
        TextField("Your note", text: $text, axis: .vertical)
            .font(.system(size: Theme.tMD))
            .foregroundColor(Theme.ink)
            .tint(Theme.accentInk)
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .accessibilityLabel("Note text")
    }

    private var actions: some View {
        HStack {
            Button("Cancel") { // gate-ok: text-labelled action
                model.cancelNoteCapture()
                dismiss()
            }
            .font(.system(size: Theme.tMD))
            .foregroundColor(Theme.ink3)
            Spacer()
            Button("Save") { // gate-ok: text-labelled action
                model.saveNote(text: text)
                dismiss()
            }
            .font(.system(size: Theme.tMD, weight: isBlank ? .regular : .semibold))
            .foregroundColor(isBlank ? Theme.ink3 : Theme.accentInk)
            .disabled(isBlank)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// Newest first — the store keeps its own ordering by timestamp.
    private var previousNotes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(previous) { note in
                    Button {
                        model.selectChapterTimestamp(note.timestamp)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.s3) {
                            Text(Fmt.hms(note.timestamp))
                                .font(.system(size: Theme.tXS))
                                .monospacedDigit()
                                .foregroundColor(Theme.ink3)
                                .frame(width: 58, alignment: .leading)
                            Text(note.text)
                                .font(.system(size: Theme.tSM))
                                .foregroundColor(Theme.ink2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Theme.s2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to note \(note.text)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var previous: [Note] {
        model.notesForCurrentBook.sorted { $0.timestamp > $1.timestamp }
    }

    private var chapterName: String {
        model.currentBook?.currentChapter?.title ?? ""
    }

    private var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
