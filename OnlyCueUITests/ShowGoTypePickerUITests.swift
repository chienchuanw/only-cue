import XCTest

/// #657 — the Show-mode GO-by-cue-type picker. The picker appears only in Show
/// mode (Cue/Lyric modes are untouched); selecting a type updates the control
/// and dims other-type rows. Movement is pinned by `MediaItemTypeFilterTests`;
/// the picker + dim are screenshot-verified here (the `.opacity` dim is not
/// directly XCUITest-queryable).
final class ShowGoTypePickerUITests: OnlyCueUITestCase {

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The GO-by-type picker, matched by its accessibility label — CueListPane
    /// stamps `cueListPane` on its whole subtree so the nested identifier is
    /// clobbered, but the "GO cue type" label survives (#657).
    private func picker(_ app: XCUIApplication) -> XCUIElement {
        app.popUpButtons.matching(NSPredicate(format: "label == %@", "GO cue type")).firstMatch
    }

    private func enterShowMode(_ app: XCUIApplication) {
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Show Mode"].click()
    }

    /// Scenario: the GO-by-type picker is Show-mode only
    /// Given a seeded document with cues of several types (Cue mode)
    /// Then the picker is absent; When the user switches to Show mode
    /// Then the picker appears.
    func test_picker_onlyVisibleInShowMode() throws {
        let app = launchApp(seed: .setListActI)

        XCTAssertTrue(element(app, "cueListPane").waitForExistence(timeout: 15))
        XCTAssertFalse(
            picker(app).exists,
            "the GO-by-type picker must not appear in Cue mode"
        )

        enterShowMode(app)
        XCTAssertTrue(
            picker(app).waitForExistence(timeout: 5),
            "the GO-by-type picker appears in Show mode"
        )
    }

    /// Scenario: selecting a type updates the picker and dims other rows
    /// Given Show mode with the type picker showing "All"
    /// When the user picks the "Teal" type
    /// Then the picker reflects "Teal" and the cue list dims other-type rows.
    func test_selectType_updatesPickerAndDimsRows() throws {
        let app = launchApp(seed: .setListActI)
        XCTAssertTrue(element(app, "cueListPane").waitForExistence(timeout: 15))
        enterShowMode(app)

        let control = picker(app)
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.click()
        app.menuItems["Teal"].click()

        XCTAssertEqual(control.value as? String, "Teal", "the picker reflects the chosen type")

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "show-go-type-picker-teal-selected"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
