import Foundation
import SwiftUI

/// Language chosen in Settings. `system` follows the device; the others pin the app's language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ko, en, ja

    static let key = "appLanguage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("시스템")
        case .ko: "한국어"
        case .en: "English"
        case .ja: "日本語"
        }
    }

    var locale: Locale? { self == .system ? nil : Locale(identifier: rawValue) }
}

enum L10n {
    /// Locale pinned in Settings, or nil to follow the system.
    static var override: Locale? {
        guard let raw = UserDefaults.standard.string(forKey: AppLanguage.key),
              let language = AppLanguage(rawValue: raw) else { return nil }
        return language.locale
    }

    static var locale: Locale { override ?? .autoupdatingCurrent }

    /// The lproj bundle for the pinned language, so model-side strings follow the in-app setting.
    static var bundle: Bundle {
        guard let override, let code = override.language.languageCode?.identifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

/// Localized string for code outside SwiftUI views (models, services, string parameters).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle, locale: L10n.locale)
}
