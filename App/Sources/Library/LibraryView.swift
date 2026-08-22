import SwiftUI

/// Library — variant A (LOCKED.md): title, filter words, search, the two
/// resume rows, then every book. Progress line rides under the cover only.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: LibraryFilter = .all
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(.system(size: Theme.t2XL, weight: .bold))
                    .padding(.top, 8)
                filterRow.padding(.top, 6)
                searchField.padding(.top, 10)

                if let listening = model.store.books.first(where: { $0.id == model.store.lastListenedID && $0.hasAudio }) {
                    sectionLabel("Listening").padding(.top, 26)
                    resumeCard(listening, reading: false).padding(.top, 8)
                }
                if let reading = model.store.books.first(where: { $0.id == model.store.lastReadID && !$0.hasAudio }) {
                    sectionLabel("Reading").padding(.top, 26)
                    resumeCard(reading, reading: true).padding(.top, 8)
                }

                sectionLabel("All books").padding(.top, 30)
                let list = filteredBooks
                if list.isEmpty {
                    Text("Nothing matches this filter.")
                        .font(.system(size: Theme.tMD))
                        .foregroundColor(Theme.ink3)
                        .padding(.top, 16)
                } else {
                    ForEach(list) { book in
                        BookRowView(book: book)
                            .contentShape(Rectangle())
                            .onTapGesture { model.openBook(book.id) }
                    }
                }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var filteredBooks: [Book] {
        LibraryQuery.books(
            from: model.store.books,
            filter: filter,
            sort: .recent,
            query: query,
            recentIDs: [model.store.lastListenedID, model.store.lastReadID].compactMap { $0 })
    }

    // MARK: pieces

    /// Quiet filter words — no pills, no boxes; weight and colour carry state.
    private var filterRow: some View {
        HStack(spacing: 18) {
            ForEach(LibraryFilter.allCases, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.label)
                        .font(.system(size: Theme.tSM))
                        .foregroundColor(f == filter ? Theme.ink : Theme.ink3)
                        .fontWeight(f == filter ? .semibold : .regular)
                }
                .accessibilityLabel("Filter \(f.label)")
                .accessibilityAddTraits(f == filter ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.tMD))
                .foregroundColor(Theme.ink3)
            TextField("Search your books", text: $query)
                .font(.system(size: Theme.tMD))
                .foregroundColor(Theme.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.ink3)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raise2))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: Theme.tXS, weight: .semibold))
            .tracking(1.1)
            .foregroundColor(Theme.ink3)
    }

    private func resumeCard(_ book: Book, reading: Bool) -> some View {
        Button {
            if reading { model.openResumeReading() } else { model.openResumeListening() }
        } label: {
            ResumeRowView(book: book, reading: reading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reading ? "Resume reading" : "Resume listening"): \(book.title)")
    }
}

/// The big resume row: cover, identity, chapter/page left, remaining right.
struct ResumeRowView: View {
    let book: Book
    let reading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CoverView(book: book)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(book.author)
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink2)
                    .lineLimit(1)
                HStack {
                    Text(leftText)
                    Spacer(minLength: 8)
                    Text(rightText)
                }
                .font(.system(size: Theme.tXS))
                .foregroundColor(Theme.ink3)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .overlay(alignment: .bottomLeading) {
            // variant A grammar: the line belongs to the cover column only
            ProgressLine(fraction: book.progress)
                .frame(width: 64)
                .offset(y: 14)
                .padding(.bottom, -14)
        }
    }

    private var leftText: String {
        if reading || !book.hasAudio {
            return book.formatWord
        }
        return book.currentChapter?.title ?? "Chapter"
    }

    private var rightText: String {
        if reading || !book.hasAudio {
            return "page \(book.page) of \(book.pageCount)"
        }
        return "\(Fmt.span(book.remaining)) left"
    }
}

/// The list row: cover with its progress line under it, then title/author/meta.
struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 5) {
                CoverView(book: book)
                    .frame(width: 64, height: 64)
                // variant A: progress under the cover, as wide as the cover
                ProgressLine(fraction: book.progress)
                    .opacity(book.progress > 0.001 && book.progress < 0.999 ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(book.author)
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink2)
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.ink3)
                    .lineLimit(1)
                    .padding(.top, 4)
                    .monospacedDigit()
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13)
        .opacity(book.progress >= 0.999 ? 0.85 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title) by \(book.author), \(meta)")
        .accessibilityAddTraits(.isButton)
    }

    private var meta: String {
        var parts: [String] = [book.formatWord]
        if book.hasAudio {
            if book.progress <= 0.001 {
                parts.append(Fmt.span(book.duration))
            } else if book.progress >= 0.999 {
                parts.append("finished")
            } else {
                parts.append("\(Fmt.span(book.remaining)) left")
            }
        } else {
            if book.progress >= 0.999 {
                parts.append("finished")
            } else {
                parts.append("page \(book.page) of \(book.pageCount)")
            }
        }
        return parts.joined(separator: " · ")
    }
}
