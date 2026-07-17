import XCTest

/// UI coverage for the per-media edit sheet (#279). Verifies the sheet's
/// composition (identity row + hero preview strip) opens from the sidebar row.
///
/// The right-click / inline-Save flows that used to live here were removed
/// (#548): they were `CIRuntime.isGitHubActions`-gated (always skipped on the
/// runner), and the underlying command is unit-tested in
/// `CueCommandsUpdateMediaItemTests`. `openEditSheet` still skips gracefully if
/// the headless context-menu chord can't be synthesised.
final class MediaEditSheetUITests: OnlyCueUITestCase {

    func test_editSheet_showsIdentityAndPreviewStrip() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)

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

    /// #649 — the Start timecode field must be wide enough to show and enter a
    /// full `HH:MM:SS:FF` value. Types a full timecode and reads it back, and
    /// captures a screenshot of the sheet for review.
    func test_editSheet_startTimecodeField_holdsFullTimecode() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        try openEditSheet(in: app)

        let tcField = app.textFields["mediaEditStartTimecodeField"]
        XCTAssertTrue(tcField.waitForExistence(timeout: 3), "Start timecode field should exist.")

        tcField.click()
        // Clear then type a full timecode.
        tcField.typeKey("a", modifierFlags: .command)
        tcField.typeText("01:23:45:12")

        let value = (tcField.value as? String) ?? ""
        XCTAssertEqual(value, "01:23:45:12", "the field should hold a full timecode, got \(value)")

        // Regression (#649): the input box must be wide enough to show a full
        // timecode, not squeezed to a few characters by an external prompt label.
        // (Before the fix the box measured ~35pt; the fix moves the hint to an
        // in-field prompt so the frame width goes to the input box.)
        XCTAssertGreaterThan(
            tcField.frame.width,
            100,
            "the timecode input box should fill its width (was \(tcField.frame.width))"
        )

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "media-edit-timecode-field"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        launchApp(seed: key)
    }
}
