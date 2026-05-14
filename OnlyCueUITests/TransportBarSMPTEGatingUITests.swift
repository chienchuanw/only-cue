import XCTest

/// Verifies the SMPTE readout in TransportBar is hidden when LTC output is
/// disabled in Settings (the fresh-launch default). The companion `LTC-on`
/// path is covered manually — toggling LTCRoutingStore from a UI test would
/// require driving Settings, which is out of scope for this gating check.
final class TransportBarSMPTEGatingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_smpteReadout_hiddenByDefault_whenLTCOutputDisabled() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        // Sanity: document opened.
        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 10),
            "document window should open within 10s of ⌘N"
        )

        // The gate under test: with LTCRoutingStore.shared.settings.isEnabled
        // == false (fresh-launch default), the SMPTE readout must be hidden.
        XCTAssertFalse(
            app.staticTexts["smpteTimecode"].exists,
            "smpteTimecode must be hidden when LTC output is disabled"
        )
    }
}
