import AppKit
import XCTest

/// UI smoke for the per-media edit sheet (#279). Right-click a sidebar media
/// row → "Edit Media…" → modal sheet opens with current values → Save commits
/// alt name / TC / mute atomically; Cancel discards drafts.
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

        let row = app.descendants(matching: .any).matching(identifier: "itemRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Sidebar media row should appear after seed opens.")

        row.rightClick()
        let editMenuItem = app.menuItems["contextMenuEditMedia"]
        XCTAssertTrue(editMenuItem.waitForExistence(timeout: 3), "Context menu 'Edit Media…' should appear.")
        editMenuItem.click()

        let nameField = app.textFields["mediaEditNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "MediaEditSheet name field should appear.")

        nameField.click()
        nameField.typeText("Opening Cue")

        let save = app.buttons["mediaEditSave"]
        XCTAssertTrue(save.exists)
        save.click()

        let renamed = app.staticTexts["Opening Cue"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 3), "Sidebar row should reflect the new alternate name after Save.")
    }

    func test_cancelDiscardsEdits() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let row = app.descendants(matching: .any).matching(identifier: "itemRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.rightClick()
        let editMenuItem = app.menuItems["contextMenuEditMedia"]
        XCTAssertTrue(editMenuItem.waitForExistence(timeout: 3))
        editMenuItem.click()

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

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }
}
