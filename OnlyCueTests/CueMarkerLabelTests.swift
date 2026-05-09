import XCTest
@testable import OnlyCue

/// Pins the format used for the cueNumber label rendered above each waveform marker.
/// The label MUST go through the canonical `FadeTime.formatNumber(_:)` formatter so
/// the marker label, the cue inspector, and the notes-overlay cue-id prefix all
/// display the same number in the same shape (whole numbers without trailing `.0`,
/// fractional numbers with a leading digit and decimal). If a future change rebuilds
/// the marker label with a private formatter, this test fails.
final class CueMarkerLabelTests: XCTestCase {

    func test_wholeNumber_rendersWithoutTrailingDecimal() {
        XCTAssertEqual(FadeTime.formatNumber(1.0), "1")
        XCTAssertEqual(FadeTime.formatNumber(2.0), "2")
        XCTAssertEqual(FadeTime.formatNumber(99.0), "99")
    }

    func test_fractionalNumber_rendersDecimal() {
        XCTAssertEqual(FadeTime.formatNumber(1.5), "1.5")
        XCTAssertEqual(FadeTime.formatNumber(2.25), "2.25")
    }
}
