import XCTest
@testable import OnlyCue

/// Figma 318:1310: only the primary play/pause control carries a filled
/// button; the prev/next skip controls are plain glyphs with no background or
/// border. Pins that rule as a pure value so the chrome decision is gated
/// renderer-independently.
final class TransportButtonChromeTests: XCTestCase {

    func test_primaryButtonShowsChrome() {
        XCTAssertTrue(TransportControls.buttonShowsChrome(primary: true))
    }

    func test_skipButtonsAreBoxless() {
        XCTAssertFalse(TransportControls.buttonShowsChrome(primary: false))
    }
}
