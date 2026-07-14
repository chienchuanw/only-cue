import SwiftUI
import XCTest
@testable import OnlyCue

/// Vertical-height math for `WaveformView`. Guards the "waveform breaks the
/// top/bottom boundary" report: normalized peaks scale the loudest bucket to
/// 1.0, and without headroom that bucket reaches the full half-height and slams
/// into the well's top and bottom edges (issue #628). The envelope must leave a
/// margin so the loudest peak never touches the boundary.
final class WaveformViewHeightTests: XCTestCase {

    func test_halfHeight_loudestPeak_leavesVerticalHeadroom() {
        let midY: CGFloat = 60
        let h = WaveformView.halfHeight(peak: 1.0, midY: midY)
        XCTAssertLessThan(h, midY, "the loudest peak must not reach the full half-height (no headroom = touches the edge)")
        XCTAssertEqual(h, midY * WaveformView.verticalFillRatio, accuracy: 0.001)
    }

    func test_halfHeight_isClampedToTheUsableBand_soItNeverTouchesTheEdge() {
        let midY: CGFloat = 60
        // A peak beyond 1.0 (defensive — normalization caps at 1.0) still must
        // not exceed the usable band.
        let h = WaveformView.halfHeight(peak: 5.0, midY: midY)
        XCTAssertLessThanOrEqual(h, midY * WaveformView.verticalFillRatio + 0.001)
        XCTAssertLessThan(h, midY)
    }

    func test_halfHeight_silence_rendersMinHairline() {
        let h = WaveformView.halfHeight(peak: 0, midY: 60)
        XCTAssertEqual(h, WaveformView.minHairline, accuracy: 0.001)
    }

    func test_verticalFillRatio_isBelowOne() {
        XCTAssertLessThan(WaveformView.verticalFillRatio, 1.0, "a ratio of 1 would reintroduce the edge-touching bug")
        XCTAssertGreaterThan(WaveformView.verticalFillRatio, 0.5, "too small would waste the well and hide dynamics")
    }
}
