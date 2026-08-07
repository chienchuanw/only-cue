import XCTest

/// Verifies the shipped zh-Hant localization renders end-to-end (catalog →
/// compiled `.lproj` → live UI), and that the hybrid glossary holds: general UI
/// is translated while entrenched lighting jargon stays English. zh-Hant
/// localization, Phase 2 (#724).
///
/// The app is forced into zh-Hant via the standard `-AppleLanguages` launch
/// argument, so this exercises the real bundle localization rather than the
/// in-app picker (whose store logic is unit-tested in `LanguagePreferenceTests`).
final class TraditionalChineseLocalizationUITests: OnlyCueUITestCase {

    private func launchChinese() -> XCUIApplication {
        launchApp(seed: .threeCuesAt1And3And6, extraArguments: ["-AppleLanguages", "(zh-Hant)"])
    }

    func test_menuBar_translatesGeneralUI_butKeepsLightingJargonInEnglish() throws {
        let app = launchChinese()
        _ = try waitForSeedWindow(in: app)

        // Translated: the Playback menu renders as 播放, and the English title
        // is gone — proving the zh-Hant column actually shipped and is in use.
        XCTAssertTrue(
            app.menuBars.menuBarItems["播放"].waitForExistence(timeout: 5),
            "the Playback menu should render as 播放 in zh-Hant"
        )
        XCTAssertFalse(
            app.menuBars.menuBarItems["Playback"].exists,
            "the English 'Playback' menu title must not appear under zh-Hant"
        )

        // Keep-English: 'Cue' is a glossary term and stays English even as the
        // surrounding UI translates.
        let cueMenu = app.menuBars.menuBarItems["Cue"]
        XCTAssertTrue(
            cueMenu.waitForExistence(timeout: 5),
            "'Cue' is a keep-English glossary term and must stay English"
        )
        cueMenu.click()

        // A menu item inside the Cue menu is fully translated.
        XCTAssertTrue(
            app.menuItems["在播放頭處複製"].waitForExistence(timeout: 3),
            "Duplicate at Playhead should be translated to 在播放頭處複製"
        )
        app.typeKey(.escape, modifierFlags: [])
    }
}
