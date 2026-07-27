import Foundation
import Testing
@testable import ImageviewCore

private enum TestBookmarkError: Error {
    case invalidData
}

private struct TestBookmarkCoder: SecurityScopedBookmarkCoding {
    let createdData: Data?
    let marksResolvedBookmarksStale: Bool

    init(
        createdData: Data? = nil,
        marksResolvedBookmarksStale: Bool = false
    ) {
        self.createdData = createdData
        self.marksResolvedBookmarksStale = marksResolvedBookmarksStale
    }

    func makeBookmark(for url: URL) throws -> Data {
        createdData ?? Data(url.path.utf8)
    }

    func resolveBookmark(
        _ data: Data,
        bookmarkDataIsStale: inout Bool
    ) throws -> URL {
        guard let path = String(data: data, encoding: .utf8),
              path.hasPrefix("/") else {
            throw TestBookmarkError.invalidData
        }
        bookmarkDataIsStale = marksResolvedBookmarksStale
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

@Test
func bookmarksPersistUsingStandardizedFolderURLs() throws {
    let suiteName = "ImageviewBookmarks.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder()
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview Bookmark \(UUID().uuidString)", isDirectory: true)
    let unstandardized = root
        .appendingPathComponent("unused", isDirectory: true)
        .appendingPathComponent("..", isDirectory: true)

    try store.save(folderURL: unstandardized)

    let restoredStore = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder()
    )
    #expect(restoredStore.restore(folderURL: root) == root.standardizedFileURL)
    #expect(restoredStore.list() == [root.standardizedFileURL])
}

@Test
func bookmarkRemovalUsesTheStandardizedFolderURL() throws {
    let suiteName = "ImageviewBookmarks.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder()
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview Bookmark \(UUID().uuidString)", isDirectory: true)
    try store.save(folderURL: root)

    store.remove(
        folderURL: root
            .appendingPathComponent("unused", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
    )

    #expect(store.restore(folderURL: root) == nil)
    #expect(store.list().isEmpty)
}

@Test
func corruptBookmarksAreRemovedAfterFailedRestore() throws {
    let suiteName = "ImageviewBookmarks.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview Bookmark \(UUID().uuidString)", isDirectory: true)
    let corruptingStore = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder(createdData: Data([0xFF]))
    )
    try corruptingStore.save(folderURL: folder)

    #expect(corruptingStore.restore(folderURL: folder) == nil)

    let replacementStore = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder()
    )
    #expect(replacementStore.restore(folderURL: folder) == nil)
    #expect(replacementStore.list().isEmpty)
}

@Test
func staleBookmarksAreRemovedAfterRestore() throws {
    let suiteName = "ImageviewBookmarks.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview Bookmark \(UUID().uuidString)", isDirectory: true)
    let staleStore = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder(marksResolvedBookmarksStale: true)
    )
    try staleStore.save(folderURL: folder)

    #expect(staleStore.restore(folderURL: folder) == nil)

    let replacementStore = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder()
    )
    #expect(replacementStore.restore(folderURL: folder) == nil)
    #expect(replacementStore.list().isEmpty)
}

@Test
func activatingAnotherSecurityScopeStopsThePreviousSuccessfulAccess() throws {
    let suiteName = "ImageviewBookmarks.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder()
    )
    let first = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview First \(UUID().uuidString)", isDirectory: true)
    let second = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview Second \(UUID().uuidString)", isDirectory: true)
    var events: [String] = []
    let access = SecurityScopedAccessSession(
        bookmarkStore: store,
        startAccessing: { url in
            events.append("start:\(url.lastPathComponent)")
            return true
        },
        stopAccessing: { url in
            events.append("stop:\(url.lastPathComponent)")
        }
    )

    #expect(access.activate(folderURL: first) == first.standardizedFileURL)
    #expect(access.activate(folderURL: second) == second.standardizedFileURL)
    access.release()

    #expect(events == [
        "start:\(first.lastPathComponent)",
        "stop:\(first.lastPathComponent)",
        "start:\(second.lastPathComponent)",
        "stop:\(second.lastPathComponent)",
    ])
    #expect(store.list() == [
        first.standardizedFileURL,
        second.standardizedFileURL,
    ])
}

@Test
func deniedSecurityScopeStartStillReturnsTheUsableFolderWithoutStopping() throws {
    let suiteName = "ImageviewBookmarks.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SecurityScopedBookmarkStore(
        defaults: defaults,
        coder: TestBookmarkCoder()
    )
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview Folder \(UUID().uuidString)", isDirectory: true)
    var startCount = 0
    var stopCount = 0
    let access = SecurityScopedAccessSession(
        bookmarkStore: store,
        startAccessing: { _ in
            startCount += 1
            return false
        },
        stopAccessing: { _ in
            stopCount += 1
        }
    )

    let usableURL = access.activate(folderURL: folder)
    access.release()

    #expect(usableURL == folder.standardizedFileURL)
    #expect(startCount == 1)
    #expect(stopCount == 0)
    #expect(store.restore(folderURL: folder) == folder.standardizedFileURL)
}
