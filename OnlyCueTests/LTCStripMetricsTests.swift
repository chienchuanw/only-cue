import XCTest
@testable import OnlyCue

/// Pins the LTC strip's tick-label metric to Figma (#553, audit `## ltc-strip`).
/// The header/ruler-inset metrics were removed in #663 when the strip lost its
/// header and its ruler became flush with the waveform's shared inset.
final class LTCStripMetricsTests: XCTestCase {

    func test_ltcStripMetrics_matchFigma() {
        XCTAssertEqual(LTCStrip.Metrics.tickLabelTop, 4)        // Figma top-[4px]
    }
}
