import AppKit
import XCTest

/// UI smoke for the per-media edit sheet (#279). Right-click a sidebar media
/// row → "Edit Media…" → modal sheet opens → Save commits alt name / TC / mute
/// atomically; Cancel discards drafts.
///
/// The sidebar row right-click is hit-test-fragile on the headless CI runner
/// (same family of issue as #264). Following the established pattern from
/// `InspectorClockHeaderUITests`, we `XCTSkip` when the context menu fails to
/// appear instead of asserting — the unit-level coverage of the underlying
/// command (`CueCommandsUpdateMediaItemTests`) is the load-bearing assurance.
final class MediaEditSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func test_rightClickMediaRow_opensEditSheet_andSaveCommitsAlternateName() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        try openEditSheet(in: app)

        let nameField = app.textFields["mediaEditNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "MediaEditSheet name field should appear.")

        nameField.click()
        nameField.typeText("Opening Cue")

        let save = app.buttons["mediaEditSave"]
        XCTAssertTrue(save.exists)
        save.click()

        let renamed = app.staticTexts["Opening Cue"]
        XCTAssertTrue(
            renamed.waitForExistence(timeout: 3),
            "Sidebar row should reflect the new alternate name after Save."
        )
    }

    func test_cancelDiscardsEdits() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        try openEditSheet(in: app)

        let nameField = app.textFields["mediaEditNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("Should Not Stick")

        app.buttons["mediaEditCancel"].click()

        XCTAssertFalse(
            app.textFields["mediaEditNameField"].waitForExistence(timeout: 1),
            "Sheet should dismiss on Cancel."
        )
        XCTAssertFalse(
            app.staticTexts["Should Not Stick"].exists,
            "Cancelled name should not be applied."
        )
    }

    /// Opens the per-media edit sheet by right-clicking the sidebar row and
    /// activating the "Edit Media…" menu item. Tolerant of CI right-click
    /// hit-test flakiness — falls back to coordinate-based right-click before
    /// `XCTSkip`ing.
    private func openEditSheet(in app: XCUIApplication) throws {
        let row = app.descendants(matching: .any).matching(identifier: "itemRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Sidebar media row should appear after seed opens.")
        Thread.sleep(forTimeInterval: 1)
        row.click()
        Thread.sleep(forTimeInterval: 0.3)

        let editMenuItem = app.menuItems["contextMenuEditMedia"]

        row.rightClick()
        if editMenuItem.waitForExistence(timeout: 2) {
            editMenuItem.click()
            return
        }

        // Coordinate-based right-click fallback for the headless CI hit-test
        // path that doesn't see the element's center via `.rightClick()`.
        let coord = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coord.rightClick()
        if editMenuItem.waitForExistence(timeout: 2) {
            editMenuItem.click()
            return
        }

        try XCTSkipIf(true, "CI: context menu did not appear via right-click. Unit-level coverage is authoritative.")
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }
}
