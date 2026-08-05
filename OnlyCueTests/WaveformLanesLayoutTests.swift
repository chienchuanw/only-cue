import XCTest
@testable import OnlyCue

final class WaveformLanesLayoutTests: XCTestCase {

    // MARK: - Two-lane split

    func test_laneHeight_dividesHeightAcrossLanesWithGaps() {
        // 200 total, 1 gap of 4 → (200 - 4) / 2 = 98
        XCTAssertEqual(
            WaveformLaneLayout.laneHeight(totalHeight: 200, laneCount: 2, gap: 4),
            98,
            accuracy: 0.001
        )
    }

    // MARK: - Single lane — no gap applied, height == totalHeight

    func test_laneHeight_singleLane_returnsTotalHeight() {
        XCTAssertEqual(
            WaveformLaneLayout.laneHeight(totalHeight: 200, laneCount: 1, gap: 4),
            200,
            accuracy: 0.001
        )
    }

    // MARK: - Three lanes

    func test_laneHeight_threeLanes() {
        // 300 total, 2 gaps of 4 → (300 - 8) / 3 = 97.333…
        let result = WaveformLaneLayout.laneHeight(totalHeight: 300, laneCount: 3, gap: 4)
        XCTAssertEqual(result, (300 - 4 * 2) / 3, accuracy: 0.001)
    }

    // MARK: - Degenerate: zero height

    func test_laneHeight_zeroTotalHeight_returnsHairlineMinimum() {
        let result = WaveformLaneLayout.laneHeight(totalHeight: 0, laneCount: 2, gap: 4)
        XCTAssertGreaterThanOrEqual(result, 1, "lane height must never be negative")
    }

    // MARK: - Degenerate: zero / negative lane count

    func test_laneHeight_zeroLaneCount_returnsHairlineMinimum() {
        let result = WaveformLaneLayout.laneHeight(totalHeight: 200, laneCount: 0, gap: 4)
        XCTAssertGreaterThanOrEqual(result, 1, "lane height must never be negative for zero lanes")
    }

    func test_laneHeight_negativeLaneCount_returnsHairlineMinimum() {
        let result = WaveformLaneLayout.laneHeight(totalHeight: 200, laneCount: -3, gap: 4)
        XCTAssertGreaterThanOrEqual(result, 1, "lane height must never be negative for negative lanes")
    }

    // MARK: - Large gap that would invert height

    func test_laneHeight_gapExceedsTotalHeight_returnsHairlineMinimum() {
        // gap*(laneCount-1) > totalHeight → raw result negative
        let result = WaveformLaneLayout.laneHeight(totalHeight: 10, laneCount: 5, gap: 100)
        XCTAssertGreaterThanOrEqual(result, 1, "floor must prevent negative lane height")
    }
}
