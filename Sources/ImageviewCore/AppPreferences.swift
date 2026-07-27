import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case en
    case zhHans = "zh-Hans"
}

public enum ShortcutCommand: String, CaseIterable, Codable, Sendable {
    case open
    case previous
    case next
    case crop
    case delete
    case grid
    case inspector
    case pin
    case ocr
}

public struct ShortcutModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct Shortcut: Equatable, Hashable, Codable, Sendable {
    public let command: ShortcutCommand
    public let key: String
    public let modifiers: ShortcutModifiers

    public init(
        command: ShortcutCommand,
        key: String,
        modifiers: ShortcutModifiers
    ) {
        self.command = command
        self.key = key.lowercased()
        self.modifiers = modifiers
    }
}

public struct ShortcutConflict: Equatable, Sendable {
    public let first: ShortcutCommand
    public let second: ShortcutCommand

    public init(first: ShortcutCommand, second: ShortcutCommand) {
        self.first = first
        self.second = second
    }
}

public enum ShortcutValidator {
    public static func conflicts(in shortcuts: [Shortcut]) -> [ShortcutConflict] {
        var conflicts: [ShortcutConflict] = []
        for firstIndex in shortcuts.indices {
            for secondIndex in shortcuts.indices where secondIndex > firstIndex {
                let first = shortcuts[firstIndex]
                let second = shortcuts[secondIndex]
                if first.key == second.key, first.modifiers == second.modifiers {
                    conflicts.append(
                        ShortcutConflict(first: first.command, second: second.command)
                    )
                }
            }
        }
        return conflicts
    }
}

public enum ShortcutPreferencesError: Error, Equatable {
    case conflict
    case invalid
}

public enum AppPreferences {
    public static let defaultThumbnailSize = 96
    public static let defaultCacheLimitMB = 512
    public static let defaultSlideshowInterval: Double = 3
    public static let defaultShortcuts = ShortcutCommand.allCases.map(defaultShortcut)

    public static func defaultShortcut(for command: ShortcutCommand) -> Shortcut {
        switch command {
        case .open: Shortcut(command: command, key: "o", modifiers: [.command])
        case .previous: Shortcut(command: command, key: "\u{F702}", modifiers: [])
        case .next: Shortcut(command: command, key: "\u{F703}", modifiers: [])
        case .crop: Shortcut(command: command, key: "k", modifiers: [.command])
        case .delete: Shortcut(command: command, key: "\u{8}", modifiers: [])
        case .grid: Shortcut(command: command, key: "g", modifiers: [])
        case .inspector: Shortcut(command: command, key: "i", modifiers: [])
        case .pin: Shortcut(command: command, key: "p", modifiers: [])
        case .ocr: Shortcut(command: command, key: "r", modifiers: [.command, .shift])
        }
    }
}

public final class PreferencesStore {
    private enum Key: String, CaseIterable {
        case thumbnailSize = "preferences.thumbnailSize"
        case language = "preferences.language"
        case singleWindow = "preferences.singleWindow"
        case closeLastWindowQuits = "preferences.closeLastWindowQuits"
        case recursiveScan = "preferences.recursiveScan"
        case wrapsNavigation = "preferences.wrapsNavigation"
        case showsThumbnails = "preferences.showsThumbnails"
        case pinOpacity = "preferences.pinOpacity"
        case cacheLimitMB = "preferences.cacheLimitMB"
        case clearsRecentItems = "preferences.clearsRecentItems"
        case shortcuts = "preferences.shortcuts"
        case slideshowInterval = "preferences.slideshowInterval"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var thumbnailSize: Int {
        get {
            guard defaults.object(forKey: Key.thumbnailSize.rawValue) != nil else {
                return AppPreferences.defaultThumbnailSize
            }
            return defaults.integer(forKey: Key.thumbnailSize.rawValue)
        }
        set {
            defaults.set(min(max(newValue, 48), 320), forKey: Key.thumbnailSize.rawValue)
        }
    }

    public var language: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: Key.language.rawValue) else {
                return .system
            }
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.language.rawValue)
        }
    }

    public var singleWindow: Bool {
        get { bool(for: .singleWindow, defaultValue: true) }
        set { defaults.set(newValue, forKey: Key.singleWindow.rawValue) }
    }

    public var closeLastWindowQuits: Bool {
        get { bool(for: .closeLastWindowQuits, defaultValue: true) }
        set { defaults.set(newValue, forKey: Key.closeLastWindowQuits.rawValue) }
    }

    public var recursiveScan: Bool {
        get { bool(for: .recursiveScan, defaultValue: false) }
        set { defaults.set(newValue, forKey: Key.recursiveScan.rawValue) }
    }

    public var wrapsNavigation: Bool {
        get { bool(for: .wrapsNavigation, defaultValue: true) }
        set { defaults.set(newValue, forKey: Key.wrapsNavigation.rawValue) }
    }

    public var showsThumbnails: Bool {
        get { bool(for: .showsThumbnails, defaultValue: true) }
        set { defaults.set(newValue, forKey: Key.showsThumbnails.rawValue) }
    }

    public var pinOpacity: Double {
        get {
            guard defaults.object(forKey: Key.pinOpacity.rawValue) != nil else {
                return 1
            }
            return defaults.double(forKey: Key.pinOpacity.rawValue)
        }
        set {
            defaults.set(min(max(newValue, 0.1), 1), forKey: Key.pinOpacity.rawValue)
        }
    }

    public var cacheLimitMB: Int {
        get {
            guard defaults.object(forKey: Key.cacheLimitMB.rawValue) != nil else {
                return AppPreferences.defaultCacheLimitMB
            }
            return defaults.integer(forKey: Key.cacheLimitMB.rawValue)
        }
        set {
            defaults.set(min(max(newValue, 64), 4_096), forKey: Key.cacheLimitMB.rawValue)
        }
    }

    public var clearsRecentItems: Bool {
        get { bool(for: .clearsRecentItems, defaultValue: false) }
        set { defaults.set(newValue, forKey: Key.clearsRecentItems.rawValue) }
    }

    public var slideshowInterval: Double {
        get {
            guard defaults.object(forKey: Key.slideshowInterval.rawValue) != nil else {
                return AppPreferences.defaultSlideshowInterval
            }
            return defaults.double(forKey: Key.slideshowInterval.rawValue)
        }
        set {
            defaults.set(
                min(max(newValue, 1), 60),
                forKey: Key.slideshowInterval.rawValue
            )
        }
    }

    public var shortcuts: [Shortcut] {
        guard let data = defaults.data(forKey: Key.shortcuts.rawValue),
              let decoded = try? PropertyListDecoder().decode([Shortcut].self, from: data),
              Self.validCommands(in: decoded) else {
            return AppPreferences.defaultShortcuts
        }
        return decoded
    }

    public func shortcut(for command: ShortcutCommand) -> Shortcut {
        shortcuts.first { $0.command == command }
            ?? AppPreferences.defaultShortcut(for: command)
    }

    public func updateShortcuts(_ shortcuts: [Shortcut]) throws {
        guard Self.validCommands(in: shortcuts),
              shortcuts.allSatisfy({ !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ShortcutPreferencesError.invalid
        }
        guard ShortcutValidator.conflicts(in: shortcuts).isEmpty else {
            throw ShortcutPreferencesError.conflict
        }
        defaults.set(
            try PropertyListEncoder().encode(shortcuts),
            forKey: Key.shortcuts.rawValue
        )
    }

    public func reset() {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    private func bool(for key: Key, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key.rawValue) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key.rawValue)
    }

    private static func validCommands(in shortcuts: [Shortcut]) -> Bool {
        Set(shortcuts.map(\.command)) == Set(ShortcutCommand.allCases)
            && shortcuts.count == ShortcutCommand.allCases.count
    }
}
