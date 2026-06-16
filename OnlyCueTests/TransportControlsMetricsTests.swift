import XCTest
@testable import OnlyCue

/// Pins the transport bar's container / divider / button metrics to Figma
/// (#555, audit `## transport-bar`). Off-grid values (no DS token);
/// renderer-independent value-pins.
final class TransportControlsMetricsTests: XCTestCase {

    func test_transportMetrics_matchFigma() {
        XCTAssertEqual(TransportControls.Metrics.containerHPadding, 16) // Figma px-16
        XCTAssertEqual(TransportControls.Metrics.containerVPadding, 10) // Figma py-10
        XCTAssertEqual(TransportControls.Metrics.zoneGap, 16)           // Figma gap-16
        XCTAssertEqual(TransportControls.Metrics.dividerHeight, 26)     // Figma h-26
        XCTAssertEqual(TransportControls.Metrics.buttonGap, 6)          // Figma gap-6
        XCTAssertEqual(TransportControls.Metrics.primaryButtonWidth, 34)
        XCTAssertEqual(TransportControls.Metrics.primaryButtonHeight, 28) // Figma 34×28
        XCTAssertEqual(TransportControls.Metrics.sideButtonWidth, 28)
        XCTAssertEqual(TransportControls.Metrics.sideButtonHeight, 26)    // Figma 28×26
    }
}
