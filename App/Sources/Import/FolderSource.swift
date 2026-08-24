import Foundation

/// A folder the user picked with the document picker, kept as a
/// security-scoped bookmark so it survives relaunches.
///
/// Two access shapes, on purpose:
/// - `withAccess` for a bounded piece of work (a scan), scope released at the
///   end of the closure;
/// - `beginAccess()` / `endAccess()` for the life of a loaded book, because
///   playback reads the file continuously and needs the scope held the whole
///   time (plan risk 5).
struct FolderSource: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Security-scoped bookmark data. Replaced when it goes stale.
    var bookmark: Data
    var displayName: String
    var addedAt: Date

    init(id: UUID = UUID(), bookmark: Data, displayName: String, addedAt: Date = Date()) {
        self.id = id
        self.bookmark = bookmark
        self.displayName = displayName
        self.addedAt = addedAt
    }

    enum ResolveError: Error, Equatable {
        /// The bookmark no longer points at anything reachable. The caller
        /// parks the folder as "needs re-picking" — it never crashes.
        case unresolvable
        /// The URL resolved but the sandbox refused the scope.
        case accessDenied
    }

    /// A resolved folder plus, when the bookmark had gone stale, the freshly
    /// minted bookmark the caller must persist.
    struct Resolution: Sendable {
        var url: URL
        /// Non-nil only when the bookmark was stale and could be re-created.
        var refreshedBookmark: Data?
    }

    // MARK: resolving

    /// Resolves the bookmark, re-creating it when stale. Does **not** start the
    /// security scope — the two access helpers below do that.
    func resolve() throws -> Resolution {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        } catch {
            throw ResolveError.unresolvable
        }
        guard isStale else { return Resolution(url: url, refreshedBookmark: nil) }
        // Re-minting a bookmark is itself a filesystem read, so it needs the scope.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fresh = try? url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return Resolution(url: url, refreshedBookmark: fresh)
    }

    /// Creates a bookmark for a freshly picked folder. Call it while the
    /// picker's own scope is still open.
    static func makeBookmark(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func make(from url: URL) throws -> FolderSource {
        FolderSource(
            bookmark: try makeBookmark(for: url),
            displayName: url.lastPathComponent)
    }

    // MARK: bounded access — one scan

    /// Resolves, holds the security scope for the duration of `body`, and
    /// releases it afterwards. The refreshed bookmark, when the resolve had to
    /// re-mint one, is handed back so the caller can persist it.
    @discardableResult
    func withAccess<T>(_ body: (URL) throws -> T) throws -> (value: T, refreshedBookmark: Data?) {
        let resolution = try resolve()
        let url = resolution.url
        guard url.startAccessingSecurityScopedResource() else {
            throw ResolveError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return (try body(url), resolution.refreshedBookmark)
    }

    /// Async twin of `withAccess`, for the indexer.
    @discardableResult
    func withAccess<T>(
        _ body: (URL) async throws -> T
    ) async throws -> (value: T, refreshedBookmark: Data?) {
        let resolution = try resolve()
        let url = resolution.url
        guard url.startAccessingSecurityScopedResource() else {
            throw ResolveError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return (try await body(url), resolution.refreshedBookmark)
    }

    // MARK: held access — the life of a loaded book

    /// An open security scope. Playback holds one of these from the moment a
    /// book is loaded until it is unloaded; dropping it early makes the engine
    /// lose the file mid-chapter.
    ///
    /// It is a class so `end()` is idempotent and the scope is released even if
    /// the owner forgets — never rely on that, but never leak either.
    final class Access {
        let url: URL
        /// Non-nil when the resolve had to re-mint the bookmark.
        let refreshedBookmark: Data?
        private var open: Bool

        init(url: URL, refreshedBookmark: Data?, open: Bool) {
            self.url = url
            self.refreshedBookmark = refreshedBookmark
            self.open = open
        }

        func end() {
            guard open else { return }
            open = false
            url.stopAccessingSecurityScopedResource()
        }

        deinit { if open { url.stopAccessingSecurityScopedResource() } }
    }

    /// Opens the scope and keeps it open until the returned token's `end()` is
    /// called. Pair every `beginAccess` with exactly one `end()`.
    func beginAccess() throws -> Access {
        let resolution = try resolve()
        let url = resolution.url
        guard url.startAccessingSecurityScopedResource() else {
            throw ResolveError.accessDenied
        }
        return Access(url: url, refreshedBookmark: resolution.refreshedBookmark, open: true)
    }
}
