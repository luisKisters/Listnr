import Foundation

/// Library filtering and sorting. Semantics mirror mockups/app.js `Phone.list`.
enum LibraryFilter: String, CaseIterable, Sendable {
    case all
    case audiobooks
    case ebooks
    case paired
    case inProgress = "in_progress"

    var label: String {
        switch self {
        case .all: return "All"
        case .audiobooks: return "Audiobooks"
        case .ebooks: return "Ebooks"
        case .paired: return "Paired"
        case .inProgress: return "In progress"
        }
    }

    func includes(_ book: Book) -> Bool {
        switch self {
        case .all: return true
        case .audiobooks: return book.hasAudio
        case .ebooks: return book.hasEbook
        case .paired: return book.isPaired
        case .inProgress: return book.progress > 0.001 && book.progress < 0.999
        }
    }
}

enum LibrarySort: String, CaseIterable, Sendable {
    case recent
    case title
    case length

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .title: return "Title"
        case .length: return "Length"
        }
    }
}

enum LibraryQuery {
    /// Filter, then search, then sort. Search matches title and author,
    /// case-insensitive; an empty query matches everything.
    static func books(
        from all: [Book],
        filter: LibraryFilter,
        sort: LibrarySort,
        query: String,
        recentIDs: [UUID] = []
    ) -> [Book] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = all.filter { book in
            guard filter.includes(book) else { return false }
            if q.isEmpty { return true }
            return book.title.lowercased().contains(q)
                || book.author.lowercased().contains(q)
        }
        return sorted(result, by: sort, recentIDs: recentIDs)
    }

    static func sorted(_ books: [Book], by sort: LibrarySort, recentIDs: [UUID] = []) -> [Book] {
        switch sort {
        case .recent:
            let rank = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($1, $0) })
            return books.sorted { a, b in
                let ra = rank[a.id] ?? Int.max
                let rb = rank[b.id] ?? Int.max
                if ra != rb { return ra < rb }
                return a.title.localizedCompare(b.title) == .orderedAscending
            }
        case .title:
            return books.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .length:
            return books.sorted { $0.duration > $1.duration }
        }
    }
}
