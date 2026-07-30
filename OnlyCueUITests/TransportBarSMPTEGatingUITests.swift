import XCTest

/// Verifies the timecode readout in TransportBar is hidden when there is
/// nothing to show: no LTC on the media file *and* LTC output disabled (the
/// fresh-launch default). Since #712 those are two independent reasons to show
/// it — a file carrying LTC displays its timecode even with output off — so
/// this asserts the remaining hidden case. Both `on` paths are covered
/// manually and by `TimecodeReadoutTests`; toggling LTCRoutingStore or
/// importing an LTC-striped file from a UI test is out of scope here.
final class TransportBarSMPTEGatingUITests: OnlyCueUITestCase {

    func test_timecodeReadout_hiddenByDefault_withNoFileTimecodeAndLTCOutputDisabled() throws {
        // A seeded document (media present) so the transport — and its SMPTE
        // readout — render; the transport is hidden in the no-media state.
        let app = launchApp(seed: .threeCuesAt1And3And6)

        // Sanity: the seeded document opened and the transport rendered.
        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 10),
            "transport should render for the seeded document within 10s"
        )

        // The seeded media carries no LTC and LTCRoutingStore.shared.settings
        // .isEnabled is false (fresh-launch default), so neither reason to show
        // the readout applies.
        XCTAssertFalse(
            app.staticTexts["smpteTimecode"].exists,
            "the timecode readout must stay hidden with no file timecode and LTC output off"
        )
    }
}
