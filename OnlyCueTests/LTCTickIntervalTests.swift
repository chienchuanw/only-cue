import XCTest
@testable import OnlyCue

/// Coverage for `LTCTickInterval.pick`: chooses the smallest seconds bucket
/// (1, 5, 15, 30, 60) where each label fits its allotted horizontal space
/// without overlapping. Pure — no SwiftUI imports.
final class LTCTickIntervalTests: XCTestCase {

    func test_pick_chooses1s_whenVeryWide() {
        XCTAssertEqual(LTCTickInterval.pick(secondsVisible: 30, pxPerSecond: 80), 1)
    }

    func test_pick_chooses60s_whenVeryNarrow() {
        XCTAssertEqual(LTCTickInterval.pick(secondsVisible: 3_600, pxPerSecond: 0.5), 60)
    }

    /// Bucket boundary: `pxPerLabel >= 56`. At 10 px/s, 5s × 10 = 50 px (< 56)
    /// so the picker must escalate to the 15s bucket (150 px ≥ 56).
    func test_pick_respects56pxMinimum_atFiveSecondBoundary() {
        XCTAssertEqual(LTCTickInterval.pick(secondsVisible: 60, pxPerSecond: 10), 15)
    }

    func test_pick_chooses5s_whenJustWideEnoughForFiveSecondLabels() {
        // 12 px/s × 5 s = 60 px (≥ 56) — 5 s bucket is sufficient.
        XCTAssertEqual(LTCTickInterval.pick(secondsVisible: 60, pxPerSecond: 12), 5)
    }

    func test_pick_zeroOrNegativePxPerSecond_fallsBackToCoarsestBucket() {
        XCTAssertEqual(LTCTickInterval.pick(secondsVisible: 30, pxPerSecond: 0), 60)
        XCTAssertEqual(LTCTickInterval.pick(secondsVisible: 30, pxPerSecond: -5), 60)
    }
}
