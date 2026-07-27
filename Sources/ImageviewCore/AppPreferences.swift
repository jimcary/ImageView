import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case en
    case zhHans = "zh-Hans"
}

public enum ShortcutCommand: String, CaseIterable, Sendable {
    case open
    case previous
    case next
    case crop
    case grid
    case inspector
    case pin
    case ocr
}

public struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct Shortcut: Equatable, Hashable, Sendable {
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

public enum AppPreferences {
    public static let defaultThumbnailSize = 96
    public static let defaultCacheLimitMB = 512
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
}
