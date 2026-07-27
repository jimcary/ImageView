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
func preferencesPersistAndResetToDocumentedDefaults() throws {
    let suiteName = "ImageviewTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(defaults: defaults)

    #expect(store.thumbnailSize == AppPreferences.defaultThumbnailSize)
    #expect(store.language == .system)
    store.thumbnailSize = 300
    store.language = .zhHans

    let restored = PreferencesStore(defaults: defaults)
    #expect(restored.thumbnailSize == 300)
    #expect(restored.language == .zhHans)

    restored.reset()
    #expect(restored.thumbnailSize == AppPreferences.defaultThumbnailSize)
    #expect(restored.language == .system)
}
