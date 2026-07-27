import Foundation
import ImageviewCore

@MainActor
enum L10n {
    private static let preferences = PreferencesStore()

    static func text(_ key: String) -> String {
        let bundle = localizedBundle()
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func localizedBundle() -> Bundle {
        switch preferences.language {
        case .system:
            return .module
        case .en:
            return languageBundle(named: "en") ?? .module
        case .zhHans:
            return languageBundle(named: "zh-Hans") ?? .module
        }
    }

    private static func languageBundle(named language: String) -> Bundle? {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
