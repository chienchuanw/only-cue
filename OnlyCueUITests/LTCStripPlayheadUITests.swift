import XCTest

/// #653 — the LTC strip shows a moving playhead while playing. This asserts the
/// playhead element renders (the wiring from `engine` through the strip's
/// `TimelineView` overlay); its per-frame movement + exact position are covered
/// by the reused `PlayheadInterpolator` / `CueMarkersGeometry` unit tests.
final class LTCStripPlayheadUITests: OnlyCueUITestCase {

    func test_ltcStrip_showsPlayhead_whilePlaying() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6, extraArguments: ["--ui-test-ltc-enabled"])

        XCTAssertTrue(
            app.buttons["transportPlayPause"].waitForExistence(timeout: 15),
            "transport should render for the seeded document"
        )
        let strip = app.descendants(matching: .any).matching(identifier: "ltcStrip").firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "the LTC strip should be visible when LTC is enabled")

        // Play → the strip's playhead appears.
        app.buttons["transportPlayPause"].click()
        let playhead = app.descendants(matching: .any).matching(identifier: "ltcStripPlayhead").firstMatch
        XCTAssertTrue(
            playhead.waitForExistence(timeout: 5),
            "the LTC strip should show a playhead while playing"
        )

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "ltc-strip-playhead"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
