import XCTest

/// End-to-end check that the LTC pill's visibility follows the user's master
/// enable switch at runtime (#796) — that the engine injected into the
/// environment by `LTCOutputHost` really reaches `PlayheadClockHeader`.
///
/// The pill is the only showtime-visible signal that LTC output is armed (and the
/// only surface that reports `LTCAudioOutput.lastError`), so "it renders when
/// enabled" is worth an end-to-end test rather than a unit test of
/// `LTCStatusLabel.isPillVisible` alone — that function already passes in
/// `LTCStatusLabelTests` while the wiring above it could still be wrong.
///
/// Both launches are hermetic via `UITestLTCHandler`, so neither reads nor writes
/// the user's real `ltcRouting.v1`, and no audio hardware is required: the pill
/// appears on the enable switch alone, before an engine ever starts.
final class LTCStatusPillUITests: OnlyCueUITestCase {

    func testPillIsHiddenWhenLTCOutputIsDisabled() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        // Wait for the clock first: it shares the header, so its presence means
        // the header has rendered and an absent pill is a real absence rather
        // than a not-yet-drawn view.
        let clock = window.descendants(matching: .staticText)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15), "playheadClock must exist")

        let pill = window.descendants(matching: .any).matching(identifier: "ltcPill").firstMatch
        XCTAssertFalse(pill.exists, "the LTC pill must not appear when LTC output is off")
    }

    func testPillAppearsWhenLTCOutputIsEnabled() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6, extraArguments: ["--ui-test-ltc-enabled"])
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .staticText)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15), "playheadClock must exist")

        let pill = window.descendants(matching: .any).matching(identifier: "ltcPill").firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the LTC pill must appear when LTC output is on")
    }
}
