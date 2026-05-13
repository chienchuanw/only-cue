import XCTest
@testable import OnlyCue

final class PlayheadOverlayTests: XCTestCase {

    func test_labelX_centersOnPlayhead_whenInsideBounds() {
        let x = PlayheadOverlay.labelX(playheadX: 100, labelWidth: 60, width: 200)
        XCTAssertEqual(x, 70, accuracy: 0.001)
    }

    func test_labelX_clampsAtLeftEdge() {
        let x = PlayheadOverlay.labelX(playheadX: 5, labelWidth: 60, width: 200)
        XCTAssertEqual(x, 0, accuracy: 0.001)
    }

    func test_labelX_clampsAtRightEdge() {
        let x = PlayheadOverlay.labelX(playheadX: 195, labelWidth: 60, width: 200)
        XCTAssertEqual(x, 140, accuracy: 0.001)
    }

    func test_labelX_handlesLabelWiderThanWaveform() {
        let x = PlayheadOverlay.labelX(playheadX: 100, labelWidth: 300, width: 200)
        XCTAssertEqual(x, 0, accuracy: 0.001)
    }

    /// Regression: the label was previously offset above the overlay's frame
    /// (negative y) and clipped by the parent ScrollView. The y inset must keep
    /// the label inside the visible viewport.
    func test_labelTopInset_isNonNegative() {
        XCTAssertGreaterThanOrEqual(PlayheadOverlay.labelTopInset, 0)
    }
}
