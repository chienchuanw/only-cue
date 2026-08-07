import Foundation

/// The user's in-app language choice. `system` follows macOS; the other cases
/// force the app's bundle localization regardless of the system language.
/// zh-Hant localization, Phase 2 (spec:
/// `docs/superpowers/specs/2026-08-06-zh-hant-localization-design.md`).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case traditionalChinese

    var id: String { rawValue }

    /// The value written to the `AppleLanguages` default, or `nil` for `system`
    /// (which clears the app-level override so the OS default applies).
    var appleLanguagesValue: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .traditionalChinese: return ["zh-Hant"]
        }
    }
}

/// Reads and writes the in-app language choice.
///
/// Two keys are kept deliberately: `choiceKey` records the user's intent (so the
/// picker can show "System" distinctly from an explicit English/Chinese pick),
/// and `AppleLanguages` is the mechanism macOS reads at launch to select the
/// bundle localization. Because macOS only consults `AppleLanguages` at launch,
/// a change takes effect after relaunch — see the General settings tab.
enum LanguagePreference {
    static let choiceKey = "OnlyCueLanguageChoice"
    static let appleLanguagesKey = "AppleLanguages"

    static func current(_ defaults: UserDefaults = .standard) -> AppLanguage {
        guard let raw = defaults.string(forKey: choiceKey),
              let language = AppLanguage(rawValue: raw) else {
            return .system
        }
        return language
    }

    static func set(_ language: AppLanguage, _ defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: choiceKey)
        if let value = language.appleLanguagesValue {
            defaults.set(value, forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
    }
}
