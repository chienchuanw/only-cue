import XCTest

/// #659 — the breakdown footer's single-lane re-show affordance. Hiding lanes
/// surfaces a "Show hidden lanes" menu (previously a one-shot "show all"
/// button); each menu item re-shows just that Type.
///
/// PreviewPane stamps `previewPane` on its whole subtree (clobbering nested
/// identifiers), so the breakdown controls are matched by their accessibility
/// *labels*, which survive. The seed's cue types have stable names — Amber,
/// Teal, Gold, Violet, Azure, Coral (model order).
///
/// Scope: this verifies the breakdown renders, per-lane hiding works, and the
/// re-show menu appears once lanes are hidden. The menu-item selection itself
/// (which Type each item re-shows) is a SwiftUI in-view `Menu` popup that
/// XCUITest can't reliably open; its logic is unit-pinned by
/// `TimelineBreakdownLayoutTests.hiddenTypes` + `CueCommands.setCuePointTypeVisibility`.
final class BreakdownReshowLaneUITests: OnlyCueUITestCase {

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func labelled(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func showBreakdown(_ app: XCUIApplication) {
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Show Timeline Breakdown"].click()
    }

    /// Scenario: hiding lanes surfaces the re-show menu
    /// Given the breakdown view
    /// When I hide the Amber and Teal lanes
    /// Then the footer offers a "Show hidden lanes" menu (not just "show all").
    func test_hidingLanes_surfacesReshowMenu() throws {
        let app = launchApp(seed: .setListActI)
        XCTAssertTrue(element(app, "previewPane").waitForExistence(timeout: 15))
        showBreakdown(app)

        // Hide the Amber and Teal lanes via their (labelled) hide buttons — their
        // existence also confirms the breakdown rendered with per-lane controls.
        let hideAmber = labelled(app, "Hide the Amber lane")
        XCTAssertTrue(hideAmber.waitForExistence(timeout: 10), "the breakdown lanes rendered")
        hideAmber.click()
        XCTAssertTrue(labelled(app, "Hide the Teal lane").waitForExistence(timeout: 5))
        labelled(app, "Hide the Teal lane").click()

        // The new single-lane re-show affordance appears once lanes are hidden.
        XCTAssertTrue(
            app.menuButtons["Show hidden lanes"].waitForExistence(timeout: 5),
            "the footer offers the hidden-lanes menu"
        )
        // Amber and Teal are gone as lanes; Gold (untouched) is still shown.
        XCTAssertFalse(labelled(app, "Hide the Amber lane").exists, "Amber lane is hidden")
        XCTAssertFalse(labelled(app, "Hide the Teal lane").exists, "Teal lane is hidden")
        XCTAssertTrue(labelled(app, "Hide the Gold lane").exists, "other lanes stay visible")

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "breakdown-two-lanes-hidden-reshow-menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
