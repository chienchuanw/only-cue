import XCTest

/// End-to-end check that the MTC pill's visibility actually follows the user's
/// enable switch at runtime (epic #794) — that the generator injected into the
/// environment by `MTCOutputHost` really does reach `PlayheadClockHeader`.
///
/// The pill is the only showtime-visible signal that MTC is armed, so "it renders
/// when enabled" is worth an end-to-end test rather than a unit test of
/// `MTCStatusLabel.isPillVisible` alone — that function already passes in
/// `MTCStatusLabelTests` while the wiring above it could still be wrong.
///
/// Both launches are hermetic via `UITestMTCHandler`, so neither reads nor writes
/// the user's real `mtcOutput.v1`, and no MIDI hardware is required: the pill
/// appears on the enable switch alone, before a destination is chosen.
final class MTCStatusPillUITests: OnlyCueUITestCase {

    func testPillIsHiddenWhenMTCOutputIsDisabled() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        // Wait for the clock first: it shares the header, so its presence means
        // the header has rendered and an absent pill is a real absence rather
        // than a not-yet-drawn view.
        let clock = window.descendants(matching: .staticText)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15), "playheadClock must exist")

        let pill = window.descendants(matching: .any).matching(identifier: "mtcPill").firstMatch
        XCTAssertFalse(pill.exists, "the MTC pill must not appear when MTC output is off")
    }

    func testPillAppearsWhenMTCOutputIsEnabled() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6, extraArguments: ["--ui-test-mtc-enabled"])
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .staticText)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15), "playheadClock must exist")

        let pill = window.descendants(matching: .any).matching(identifier: "mtcPill").firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the MTC pill must appear when MTC output is on")
    }
}
