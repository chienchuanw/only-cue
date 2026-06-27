import XCTest

/// Verifies the SMPTE readout in TransportBar is hidden when LTC output is
/// disabled in Settings (the fresh-launch default). The companion `LTC-on`
/// path is covered manually — toggling LTCRoutingStore from a UI test would
/// require driving Settings, which is out of scope for this gating check.
final class TransportBarSMPTEGatingUITests: OnlyCueUITestCase {

    func test_smpteReadout_hiddenByDefault_whenLTCOutputDisabled() throws {
        // A seeded document (media present) so the transport — and its SMPTE
        // readout — render; the transport is hidden in the no-media state.
        let app = launchApp(seed: .threeCuesAt1And3And6)

        // Sanity: the seeded document opened and the transport rendered.
        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 10),
            "transport should render for the seeded document within 10s"
        )

        // The gate under test: with LTCRoutingStore.shared.settings.isEnabled
        // == false (fresh-launch default), the SMPTE readout must be hidden.
        XCTAssertFalse(
            app.staticTexts["smpteTimecode"].exists,
            "smpteTimecode must be hidden when LTC output is disabled"
        )
    }
}
