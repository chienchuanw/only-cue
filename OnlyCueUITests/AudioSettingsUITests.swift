import XCTest

/// Behaviour of the Settings → Audio pane's "Enable LTC output" master toggle:
/// off by default with the channel-routing table hidden; toggling it on reveals
/// the device picker and per-channel role table; toggling it off hides them again.
final class AudioSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_enableToggle_revealsAndHidesChannelTable() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["playPauseButton"].waitForExistence(timeout: 5),
            "a document window should open within 5 seconds"
        )

        let windowsBefore = app.windows.count
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(
            SettingsWindowFinder.waitForNewWindow(in: app, above: windowsBefore, timeout: 5),
            "pressing Command-comma should open the Settings window"
        )

        let audioTab = app.radioButtons["Audio"].exists ? app.radioButtons["Audio"] : app.buttons["Audio"]
        if audioTab.waitForExistence(timeout: 3) {
            audioTab.click()
        }

        let toggle = enableToggle(in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the Enable LTC output toggle should appear in the Audio pane")

        // Default: LTC disabled — the channel-routing table is hidden.
        XCTAssertFalse(app.popUpButtons["audioChannelRolePicker.0"].exists, "channel table hidden when LTC is off")
        XCTAssertFalse(app.popUpButtons["audioOutputDevicePicker"].exists, "device picker hidden when LTC is off")

        toggle.click()
        XCTAssertTrue(
            app.popUpButtons["audioChannelRolePicker.0"].waitForExistence(timeout: 3),
            "enabling LTC should reveal the channel table"
        )
        XCTAssertTrue(app.popUpButtons["audioOutputDevicePicker"].exists, "enabling LTC should reveal the device picker")

        enableToggle(in: app).click()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.popUpButtons["audioChannelRolePicker.0"], handler: nil)
        waitForExpectations(timeout: 3)

        app.terminate()
    }

    /// The "Enable LTC output" control — a SwiftUI `Toggle`, which surfaces as a
    /// checkbox on macOS but is matched here through either element type for
    /// robustness across OS versions.
    private func enableToggle(in app: XCUIApplication) -> XCUIElement {
        let checkBox = app.checkBoxes["enableLTCOutputToggle"]
        return checkBox.exists ? checkBox : app.switches["enableLTCOutputToggle"]
    }
}
