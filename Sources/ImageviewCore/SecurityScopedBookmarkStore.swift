import Foundation

protocol SecurityScopedBookmarkCoding {
    func makeBookmark(for url: URL) throws -> Data
    func resolveBookmark(
        _ data: Data,
        bookmarkDataIsStale: inout Bool
    ) throws -> URL
}

private struct SystemSecurityScopedBookmarkCoder: SecurityScopedBookmarkCoding {
    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(
        _ data: Data,
        bookmarkDataIsStale: inout Bool
    ) throws -> URL {
        try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkDataIsStale
        )
    }
}

public final class SecurityScopedBookmarkStore {
    private static let storageKey = "securityScopedBookmarks.folders"

    private let defaults: UserDefaults
    private let coder: any SecurityScopedBookmarkCoding

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, coder: SystemSecurityScopedBookmarkCoder())
    }

    init(
        defaults: UserDefaults,
        coder: any SecurityScopedBookmarkCoding
    ) {
        self.defaults = defaults
        self.coder = coder
    }

    public func save(folderURL: URL) throws {
        let folderURL = folderURL.standardizedFileURL
        let data = try coder.makeBookmark(for: folderURL)
        var bookmarks = storedBookmarks()
        bookmarks[storageKey(for: folderURL)] = data
        persist(bookmarks)
    }

    public func restore(folderURL: URL) -> URL? {
        let key = storageKey(for: folderURL)
        var bookmarks = storedBookmarks()
        guard let data = bookmarks[key] else {
            return nil
        }

        do {
            var isStale = false
            let url = try coder.resolveBookmark(
                data,
                bookmarkDataIsStale: &isStale
            )
            guard !isStale else {
                bookmarks.removeValue(forKey: key)
                persist(bookmarks)
                return nil
            }
            return url.standardizedFileURL
        } catch {
            bookmarks.removeValue(forKey: key)
            persist(bookmarks)
            return nil
        }
    }

    public func list() -> [URL] {
        var bookmarks = storedBookmarks()
        var urls: [URL] = []
        var removedInvalidBookmark = false

        for key in bookmarks.keys.sorted() {
            guard let data = bookmarks[key] else {
                continue
            }
            do {
                var isStale = false
                let url = try coder.resolveBookmark(
                    data,
                    bookmarkDataIsStale: &isStale
                )
                guard !isStale else {
                    bookmarks.removeValue(forKey: key)
                    removedInvalidBookmark = true
                    continue
                }
                urls.append(url.standardizedFileURL)
            } catch {
                bookmarks.removeValue(forKey: key)
                removedInvalidBookmark = true
            }
        }

        if removedInvalidBookmark {
            persist(bookmarks)
        }
        return urls
    }

    public func remove(folderURL: URL) {
        var bookmarks = storedBookmarks()
        bookmarks.removeValue(forKey: storageKey(for: folderURL))
        persist(bookmarks)
    }

    private func storedBookmarks() -> [String: Data] {
        defaults.dictionary(forKey: Self.storageKey)?
            .compactMapValues { $0 as? Data } ?? [:]
    }

    private func persist(_ bookmarks: [String: Data]) {
        if bookmarks.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(bookmarks, forKey: Self.storageKey)
        }
    }

    private func storageKey(for folderURL: URL) -> String {
        folderURL.standardizedFileURL.absoluteString
    }
}

public final class SecurityScopedAccessSession {
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let startAccessing: (URL) -> Bool
    private let stopAccessing: (URL) -> Void
    private var activeURL: URL?
    private var didStartAccess = false

    public convenience init(
        bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore()
    ) {
        self.init(
            bookmarkStore: bookmarkStore,
            startAccessing: { $0.startAccessingSecurityScopedResource() },
            stopAccessing: { $0.stopAccessingSecurityScopedResource() }
        )
    }

    init(
        bookmarkStore: SecurityScopedBookmarkStore,
        startAccessing: @escaping (URL) -> Bool,
        stopAccessing: @escaping (URL) -> Void
    ) {
        self.bookmarkStore = bookmarkStore
        self.startAccessing = startAccessing
        self.stopAccessing = stopAccessing
    }

    deinit {
        release()
    }

    @discardableResult
    public func activate(folderURL: URL) -> URL {
        release()

        let folderURL = folderURL.standardizedFileURL
        try? bookmarkStore.save(folderURL: folderURL)
        let usableURL = bookmarkStore.restore(folderURL: folderURL) ?? folderURL
        didStartAccess = startAccessing(usableURL)
        activeURL = usableURL
        return usableURL
    }

    public func release() {
        if didStartAccess, let activeURL {
            stopAccessing(activeURL)
        }
        activeURL = nil
        didStartAccess = false
    }
}
