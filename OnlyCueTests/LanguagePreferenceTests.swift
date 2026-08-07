import XCTest
@testable import OnlyCue

final class LanguagePreferenceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // A clean suite name — `self.name` contains `[`, `]`, and spaces, which
        // are invalid in a UserDefaults domain and silently break isolation.
        suiteName = "LanguagePreferenceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_default_isSystem_whenNoChoiceStored() {
        XCTAssertEqual(LanguagePreference.current(defaults), .system)
    }

    func test_appleLanguagesValue_mapping() {
        XCTAssertNil(AppLanguage.system.appleLanguagesValue)
        XCTAssertEqual(AppLanguage.english.appleLanguagesValue, ["en"])
        XCTAssertEqual(AppLanguage.traditionalChinese.appleLanguagesValue, ["zh-Hant"])
    }

    func test_setTraditionalChinese_persistsChoiceAndAppleLanguages() {
        LanguagePreference.set(.traditionalChinese, defaults)
        XCTAssertEqual(LanguagePreference.current(defaults), .traditionalChinese)
        XCTAssertEqual(
            defaults.stringArray(forKey: LanguagePreference.appleLanguagesKey),
            ["zh-Hant"]
        )
    }

    func test_setEnglish_forcesEnglishAppleLanguages() {
        LanguagePreference.set(.english, defaults)
        XCTAssertEqual(LanguagePreference.current(defaults), .english)
        XCTAssertEqual(defaults.stringArray(forKey: LanguagePreference.appleLanguagesKey), ["en"])
    }

    func test_setSystem_removesAppleLanguagesOverride() {
        LanguagePreference.set(.traditionalChinese, defaults)
        LanguagePreference.set(.system, defaults)
        XCTAssertEqual(LanguagePreference.current(defaults), .system)
        // Check the app's own persistent domain, not the merged lookup:
        // `stringArray(forKey:)` falls through to NSGlobalDomain (which always
        // carries the system languages), so removal is only observable here.
        let domain = defaults.persistentDomain(forName: suiteName)
        XCTAssertNil(
            domain?[LanguagePreference.appleLanguagesKey],
            "System must clear the app-level AppleLanguages override so the OS default applies"
        )
    }

    func test_allCases_coverThreeOptions() {
        XCTAssertEqual(AppLanguage.allCases, [.system, .english, .traditionalChinese])
    }
}
