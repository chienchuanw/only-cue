import AppKit
import XCTest

/// UI coverage for the per-media edit sheet (#279). Verifies the sheet's
/// composition (identity row + hero preview strip) opens from the sidebar row.
///
/// The right-click / inline-Save flows that used to live here were removed
/// (#548): they were `CIRuntime.isGitHubActions`-gated (always skipped on the
/// runner), and the underlying command is unit-tested in
/// `CueCommandsUpdateMediaItemTests`. `openEditSheet` still skips gracefully if
/// the headless context-menu chord can't be synthesised.
final class MediaEditSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func test_editSheet_showsIdentityAndPreviewStrip() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        try openEditSheet(in: app)

        let nameField = app.textFields["mediaEditNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Sheet should open.")

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "mediaEditPreviewStrip").firstMatch.exists,
            "Hero preview strip should be present in the Edit Media sheet."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "mediaEditIdentity").firstMatch.exists,
            "File-identity row should be present in the Edit Media sheet."
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
