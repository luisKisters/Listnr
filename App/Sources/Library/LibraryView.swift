import SwiftUI

/// Library — variant B (LOCKED.md): one title row with the filter as a header
/// value, search, the two resume rows, then every book. Progress is a band
/// inside the cover's own bottom edge; nothing draws a line outside a cover.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: LibraryFilter = .all
    @State private var query = ""
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow.padding(.top, Theme.s2)
                searchField.padding(.top, Theme.s3)

                if let listening = model.store.books.first(where: { $0.id == model.store.lastListenedID && $0.hasAudio }) {
                    sectionLabel("Listening")
                    resumeCard(listening, reading: false).padding(.top, Theme.s1)
                }
                if let reading = model.store.books.first(where: { $0.id == model.store.lastReadID && !$0.hasAudio }) {
                    sectionLabel("Reading")
                    resumeCard(reading, reading: true).padding(.top, Theme.s1)
                }

                sectionLabel("All books")
                let list = filteredBooks
                if list.isEmpty {
                    Text("Nothing matches this filter.")
                        .font(.system(size: Theme.tMD))
                        .foregroundColor(Theme.ink3)
                        .padding(.top, Theme.s4)
                } else {
                    ForEach(list) { book in
                        BookRowView(book: book)
                            .contentShape(Rectangle())
                            .onTapGesture { model.openBook(book.id) }
                    }
                }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.bottom, Theme.s5)
        }
        .background(Theme.bg)
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $importing) { importSheetShell }
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

    /// kit.css `.titlerow`: the heading, the filter value, the add control.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: Theme.s3) {
            Text("Library")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.035 * 30)
            Spacer(minLength: Theme.s3)
            filterMenu
            Button {
                importing = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.ink2)
            }
            .accessibilityLabel("Add books")
        }
    }

    /// kit.css `.drop`: a value plus a caret, nothing drawn around it.
    private var filterMenu: some View {
        Menu {
            ForEach(LibraryFilter.allCases, id: \.self) { option in
                Button {
                    filter = option
                } label: {
                    if option == filter {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
                .accessibilityLabel(option.label)
            }
        } label: {
            HStack(spacing: 5) {
                Text(filter.label)
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 14))
            .foregroundColor(Theme.ink2)
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(filter.label)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.tMD))
                .foregroundColor(Theme.ink3)
            TextField("Search your books", text: $query)
                .font(.system(size: 14))
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
        .padding(.horizontal, 9)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raise2))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.1 * 11)
            .foregroundColor(Theme.ink3)
            .padding(.top, Theme.s5)
            .padding(.bottom, Theme.s1)
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

    /// Shell for step 5's import sheet: the folder row is inert on purpose, so
    /// the "+" control always has visible feedback instead of doing nothing.
    private var importSheetShell: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.s2) {
                HStack(spacing: Theme.s3) {
                    Image(systemName: "folder")
                    Text("Folder — M4B")
                        .font(.system(size: Theme.tMD))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.ink3)
                .frame(height: 44)
                Text("Importing arrives with the next step.")
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, Theme.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg)
            .navigationTitle("Add books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { importing = false }
                        .accessibilityLabel("Cancel import")
                }
            }
        }
    }
}

/// The big resume row: cover with its band, identity, chapter left / remaining right.
struct ResumeRowView: View {
    let book: Book
    let reading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CoverView(book: book, progress: band)
                .frame(width: Theme.cover, height: Theme.cover)
            VStack(alignment: .leading, spacing: 0) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.015 * 16)
                    .lineLimit(1)
                    .frame(height: 20, alignment: .leading)
                Text(book.author)
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink2)
                    .lineLimit(1)
                    .frame(height: 16, alignment: .leading)
                HStack(spacing: Theme.s2) {
                    Text(leftText).lineLimit(1)
                    Spacer(minLength: Theme.s2)
                    Text(rightText).lineLimit(1)
                }
                .font(.system(size: 11.5))
                .foregroundColor(Theme.ink3)
                .monospacedDigit()
                .frame(height: 16)
                .padding(.top, Theme.s1 + 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var band: Double? { book.progress > 0.001 ? book.progress : nil }

    private var leftText: String {
        if reading || !book.hasAudio {
            return book.formatWord
        }
        // No container chapters: the chapter part drops out entirely.
        return book.currentChapter?.title ?? book.formatWord
    }

    private var rightText: String {
        if reading || !book.hasAudio {
            return "page \(book.page) of \(book.pageCount)"
        }
        return "\(Fmt.span(book.remaining)) left"
    }
}

/// The list row: the cover carries the progress band, then title/author/meta.
struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CoverView(book: book, progress: band)
                .frame(width: Theme.cover, height: Theme.cover)
            VStack(alignment: .leading, spacing: 0) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.01 * 14)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 18, alignment: .leading)
                Text(book.author)
                    .font(.system(size: Theme.tXS))
                    .foregroundColor(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 16, alignment: .leading)
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .monospacedDigit()
                    .frame(height: 16, alignment: .leading)
                    .padding(.top, Theme.s1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.s3)
        .opacity(band == nil ? 0.66 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title) by \(book.author), \(meta)")
        .accessibilityAddTraits(.isButton)
    }

    private var band: Double? { book.progress > 0.001 ? book.progress : nil }

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
