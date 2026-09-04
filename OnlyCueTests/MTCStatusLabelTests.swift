import XCTest
@testable import OnlyCue

/// `MTCStatusLabel` is the pure copy + state machine behind both MTC status
/// surfaces (epic #794): the row in Settings ▸ MIDI and the pill beside the
/// playhead clock. Follows `LTCBadgeLabel`, which pins its formatting the same way.
final class MTCStatusLabelTests: XCTestCase {

    // MARK: - State

    func test_state_offWhenDisabled() {
        XCTAssertEqual(
            MTCStatusLabel.state(isComplete: false, isRunning: false, lastError: nil),
            .off
        )
    }

    // A destination that vanished must read as failed even though the switch is
    // still on — this is the unplugged-mid-show case.
    func test_state_failedWhenAnErrorIsPresent() {
        XCTAssertEqual(
            MTCStatusLabel.state(isComplete: true, isRunning: false, lastError: "gone"),
            .failed
        )
        XCTAssertEqual(
            MTCStatusLabel.state(isComplete: true, isRunning: true, lastError: "gone"),
            .failed
        )
    }

    func test_state_readyWhenConfiguredButIdle() {
        XCTAssertEqual(
            MTCStatusLabel.state(isComplete: true, isRunning: false, lastError: nil),
            .ready
        )
    }

    func test_state_sendingWhenRunning() {
        XCTAssertEqual(
            MTCStatusLabel.state(isComplete: true, isRunning: true, lastError: nil),
            .sending
        )
    }

    // MARK: - Status text

    func test_statusText_namesWhatIsWrongWhenFailed() {
        XCTAssertEqual(
            MTCStatusLabel.statusText(state: .failed, timecode: nil, lastError: "The destination is unavailable."),
            "The destination is unavailable."
        )
    }

    // A failed state with no message still has to say something useful.
    func test_statusText_failedWithoutAMessageStillReads() {
        XCTAssertEqual(
            MTCStatusLabel.statusText(state: .failed, timecode: nil, lastError: nil),
            "MTC output failed."
        )
    }

    func test_statusText_showsTheLiveTimecodeWhileSending() {
        XCTAssertEqual(
            MTCStatusLabel.statusText(state: .sending, timecode: "01:00:04:12", lastError: nil),
            "Sending — 01:00:04:12"
        )
    }

    // Sending before the first readout lands must not print an empty dash tail.
    func test_statusText_sendingWithoutATimecodeYet() {
        XCTAssertEqual(
            MTCStatusLabel.statusText(state: .sending, timecode: nil, lastError: nil),
            "Sending"
        )
    }

    func test_statusText_offAndReadyExplainThemselves() {
        XCTAssertEqual(
            MTCStatusLabel.statusText(state: .off, timecode: nil, lastError: nil),
            "Not sending — enable MTC and choose a destination."
        )
        XCTAssertEqual(
            MTCStatusLabel.statusText(state: .ready, timecode: nil, lastError: nil),
            "Ready — sends on play."
        )
    }

    // MARK: - Pill

    // The pill is a fixed, short token so the transport bar's layout cannot
    // shift as timecode advances.
    func test_pillText_isAStableToken() {
        XCTAssertEqual(MTCStatusLabel.pillText, "MTC")
    }

    // The pill is only worth showing once MTC is switched on; an unconfigured
    // install must not carry dead chrome.
    func test_isPillVisible_followsTheEnableSwitch() {
        XCTAssertTrue(MTCStatusLabel.isPillVisible(isEnabled: true))
        XCTAssertFalse(MTCStatusLabel.isPillVisible(isEnabled: false))
    }
}
