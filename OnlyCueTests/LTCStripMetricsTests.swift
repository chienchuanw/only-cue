import XCTest
@testable import OnlyCue

/// Pins the LTC strip header/ruler metrics to Figma (#553, audit `## ltc-strip`).
/// Off-grid values (no DS token) that would otherwise silently drift toward the
/// 4px grid; renderer-independent value-pins.
final class LTCStripMetricsTests: XCTestCase {

    func test_ltcStripMetrics_matchFigma() {
        XCTAssertEqual(LTCStrip.Metrics.headerGap, 6)            // Figma gap-[6px]
        XCTAssertEqual(LTCStrip.Metrics.headerHPadding, 10)      // Figma px-[10px]
        XCTAssertEqual(LTCStrip.Metrics.iconWidth, 17)          // Figma 17×14
        XCTAssertEqual(LTCStrip.Metrics.iconHeight, 14)
        XCTAssertEqual(LTCStrip.Metrics.rulerLeadingInset, 8)   // Figma pl-[8px]
        XCTAssertEqual(LTCStrip.Metrics.tickLabelTop, 4)        // Figma top-[4px]
    }
}
