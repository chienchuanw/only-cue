import XCTest
@testable import OnlyCue

/// `LTCStatusLabel` is the pure copy + state machine behind the LTC status pill
/// beside the playhead clock (#796). It closes the same showtime-invisibility gap
/// `MTCStatusLabel` closed for MIDI Timecode (#794): `LTCAudioOutput.lastError`
/// was published but unread, so an unplugged interface stopped timecode silently.
final class LTCStatusLabelTests: XCTestCase {

    // MARK: - State

    func test_state_offWhenNotComplete() {
        XCTAssertEqual(
            LTCStatusLabel.state(isComplete: false, isRunning: false, lastError: nil),
            .off
        )
    }

    // The routed interface that vanished must read as failed even while the
    // engine still believes it is running — the unplugged-mid-show case.
    func test_state_failedWhenAnErrorIsPresent() {
        XCTAssertEqual(
            LTCStatusLabel.state(isComplete: true, isRunning: false, lastError: "gone"),
            .failed
        )
        XCTAssertEqual(
            LTCStatusLabel.state(isComplete: true, isRunning: true, lastError: "gone"),
            .failed
        )
    }

    func test_state_readyWhenConfiguredButIdle() {
        XCTAssertEqual(
            LTCStatusLabel.state(isComplete: true, isRunning: false, lastError: nil),
            .ready
        )
    }

    func test_state_sendingWhenRunning() {
        XCTAssertEqual(
            LTCStatusLabel.state(isComplete: true, isRunning: true, lastError: nil),
            .sending
        )
    }

    // MARK: - Status text

    func test_statusText_namesWhatIsWrongWhenFailed() {
        XCTAssertEqual(
            LTCStatusLabel.statusText(state: .failed, timecode: nil, lastError: "The selected audio output device is unavailable."),
            "The selected audio output device is unavailable."
        )
    }

    // A failed state with no message still has to say something useful.
    func test_statusText_failedWithoutAMessageStillReads() {
        XCTAssertEqual(
            LTCStatusLabel.statusText(state: .failed, timecode: nil, lastError: nil),
            "LTC output failed."
        )
    }

    // LTC publishes no live timecode, but the label keeps the MTC signature so
    // the two surfaces stay interchangeable; a supplied timecode is still shown.
    func test_statusText_showsTheTimecodeWhileSendingIfGiven() {
        XCTAssertEqual(
            LTCStatusLabel.statusText(state: .sending, timecode: "01:00:04:12", lastError: nil),
            "Sending — 01:00:04:12"
        )
    }

    // The pill sits beside the giant playhead clock, so LTC passes no timecode
    // and the label must not print an empty dash tail.
    func test_statusText_sendingWithoutATimecode() {
        XCTAssertEqual(
            LTCStatusLabel.statusText(state: .sending, timecode: nil, lastError: nil),
            "Sending"
        )
    }

    func test_statusText_offAndReadyExplainThemselves() {
        XCTAssertEqual(
            LTCStatusLabel.statusText(state: .off, timecode: nil, lastError: nil),
            "Not sending — enable LTC and assign an output channel."
        )
        XCTAssertEqual(
            LTCStatusLabel.statusText(state: .ready, timecode: nil, lastError: nil),
            "Ready — sends on play."
        )
    }

    // MARK: - Pill

    // A fixed, short token so the transport bar's layout cannot shift.
    func test_pillText_isAStableToken() {
        XCTAssertEqual(LTCStatusLabel.pillText, "LTC")
    }

    // The pill follows the master enable switch, so an unconfigured install
    // carries no dead chrome and an armed-but-idle rig is still visible.
    func test_isPillVisible_followsTheEnableSwitch() {
        XCTAssertTrue(LTCStatusLabel.isPillVisible(isEnabled: true))
        XCTAssertFalse(LTCStatusLabel.isPillVisible(isEnabled: false))
    }
}
