import SwiftUI

/// Timestamped note capture. Playback is already paused by the time this sheet
/// appears; saving or dismissing resumes it when it was playing before.
struct NoteSheetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let book = model.currentBook {
                    HStack(spacing: 10) {
                        CoverView(book: book)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.system(size: Theme.tSM, weight: .semibold))
                                .lineLimit(1)
                            Text("at \(Fmt.hms(model.engine.position))")
                                .font(.system(size: Theme.tXS))
                                .foregroundColor(Theme.ink3)
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                }
                TextField("Your note", text: $text, axis: .vertical)
                    .font(.system(size: Theme.tLG))
                    .focused($focused)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raise2))
                    .accessibilityLabel("Note text")
                Text("Playback resumes when you save.")
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink3)
                let existing = model.notesForCurrentBook
                if !existing.isEmpty {
                    Text("Notes for this book")
                        .font(.system(size: Theme.tXS, weight: .semibold))
                        .tracking(1.1)
                        .foregroundColor(Theme.ink3)
                        .textCase(.uppercase)
                        .padding(.top, 6)
                    ForEach(existing) { note in
                        Button {
                            model.selectChapterTimestamp(note.timestamp)
                            dismiss()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(Fmt.hms(note.timestamp))
                                    .font(.system(size: Theme.tXS, weight: .semibold))
                                    .foregroundColor(Theme.accentInk)
                                    .monospacedDigit()
                                Text(note.text)
                                    .font(.system(size: Theme.tSM))
                                    .foregroundColor(Theme.ink2)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.ink3)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Jump to note \(note.text)")
                    }
                }
                Spacer()
            }
            .padding(Theme.inset)
            .background(Theme.bg)
            .navigationTitle("New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancelNoteCapture()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveNote(text: text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .preferredColorScheme(.dark)
    }
}

/// Notes list for the current book with jump-to-timestamp.
struct NotesListView: View {
    let notes: [Note]
    let onJump: (Note) -> Void
    let onDelete: (Note) -> Void

    var body: some View {
        List {
            ForEach(notes) { note in
                Button {
                    onJump(note)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.hms(note.timestamp))
                            .font(.system(size: Theme.tXS, weight: .semibold))
                            .foregroundColor(Theme.accentInk)
                            .monospacedDigit()
                        Text(note.text.isEmpty ? "(empty)" : note.text)
                            .font(.system(size: Theme.tMD))
                            .foregroundColor(Theme.ink)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .onDelete { indexSet in
                for i in indexSet {
                    guard i < notes.count else { continue }
                    onDelete(notes[i])
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
    }
}
