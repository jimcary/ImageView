import Foundation
import Testing
@testable import ImageviewCore

@Test
func duplicateShortcutReportsBothCommands() {
    let shortcuts = [
        Shortcut(command: .next, key: "j", modifiers: []),
        Shortcut(command: .previous, key: "j", modifiers: []),
        Shortcut(command: .crop, key: "c", modifiers: [.command]),
    ]

    let conflicts = ShortcutValidator.conflicts(in: shortcuts)

    #expect(conflicts == [
        ShortcutConflict(first: .next, second: .previous),
    ])
}

@Test
func cropAndDeleteUseTheRequestedDefaultShortcuts() {
    #expect(
        AppPreferences.defaultShortcut(for: .crop)
            == Shortcut(command: .crop, key: "k", modifiers: [.command])
    )
    #expect(
        AppPreferences.defaultShortcut(for: .delete)
            == Shortcut(command: .delete, key: "\u{7F}", modifiers: [])
    )
}

@Test
func preferencesPersistAndResetToDocumentedDefaults() throws {
    let suiteName = "ImageviewTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(defaults: defaults)

    #expect(store.thumbnailSize == AppPreferences.defaultThumbnailSize)
    #expect(store.language == .system)
    store.thumbnailSize = 300
    store.language = .zhHans
    store.slideshowInterval = 4.5

    let restored = PreferencesStore(defaults: defaults)
    #expect(restored.thumbnailSize == 300)
    #expect(restored.language == .zhHans)
    #expect(restored.slideshowInterval == 4.5)

    restored.reset()
    #expect(restored.thumbnailSize == AppPreferences.defaultThumbnailSize)
    #expect(restored.language == .system)
    #expect(restored.slideshowInterval == AppPreferences.defaultSlideshowInterval)
}

@Test
func shortcutsPersistAndConflictsAreRejectedWithoutChangingStoredValues() throws {
    let suiteName = "ImageviewTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(defaults: defaults)
    var shortcuts = store.shortcuts
    let previousIndex = try #require(shortcuts.firstIndex { $0.command == .previous })
    shortcuts[previousIndex] = Shortcut(
        command: .previous,
        key: "b",
        modifiers: [.command]
    )

    try store.updateShortcuts(shortcuts)
    #expect(PreferencesStore(defaults: defaults).shortcuts == shortcuts)

    var conflicting = shortcuts
    let nextIndex = try #require(conflicting.firstIndex { $0.command == .next })
    conflicting[nextIndex] = Shortcut(
        command: .next,
        key: "b",
        modifiers: [.command]
    )

    #expect(throws: ShortcutPreferencesError.conflict) {
        try store.updateShortcuts(conflicting)
    }
    #expect(store.shortcuts == shortcuts)
}
