import XCTest

/// The `View -> Show Lyrics Overlay` playback HUD. Launches a seeded document
/// that already carries lyrics, toggles the overlay, and asserts the HUD shows
/// the active line. The HUD is a main-window overlay (not sheet content), so
/// its rendered text is reliably queryable on the CI runner.
final class LyricsOverlayUITests: OnlyCueUITestCase {

    /// One-call-per-line element lookup by identifier.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    /// Scenario: the lyrics HUD appears when toggled on for a doc with lyrics
    /// Given a seeded document that carries lyrics is open
    /// When the user enables View -> Show Lyrics Overlay
    /// Then the HUD shows the lyric line active at the playhead.
    func test_showLyricsOverlay_displaysActiveLine() throws {
        let app = launchApp(seed: .songWithLyrics)

        XCTAssertTrue(
            element("previewPane", in: app).waitForExistence(timeout: 15),
            "seed document should open"
        )

        app.menuBars.menuBarItems["View"].click()
        // The menu item title flips between "Show Lyrics Overlay" and
        // "Hide Lyrics Overlay" based on @AppStorage state, which persists
        // across runs. On a developer's Mac this state is shared with
        // their real app usage. macOS XCUITest also does not expose the
        // SwiftUI `.accessibilityIdentifier(...)` on NSMenuItem — menu
        // items are matchable only by title — so we look up both possible
        // titles and click only when the overlay is currently off.
        let showItem = app.menuItems["Show Lyrics Overlay"]
        let hideItem = app.menuItems["Hide Lyrics Overlay"]
        if showItem.waitForExistence(timeout: 3) {
            showItem.click()
        } else if hideItem.exists {
            // Already on — dismiss the menu; the HUD assertion below still
            // verifies the overlay is visible.
            app.typeKey(.escape, modifierFlags: [])
        } else {
            XCTFail("View menu should offer the lyrics overlay toggle (either Show or Hide title)")
        }

        XCTAssertTrue(
            app.staticTexts["Seeded opening line"].waitForExistence(timeout: 5),
            "the lyrics HUD should show the line active at the opening playhead"
        )
    }
}
