import XCTest
@testable import OnlyCue

final class MiniPlaybackActionsTests: XCTestCase {

    func test_rateChangeMapping() {
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateUp), .up)
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateDown), .down)
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateReset), .reset)
        XCTAssertNil(MiniPlaybackActions.rateChange(for: .playPause))
    }

    // MARK: - Absolute seek (#758)

    func test_seekTarget_mapsFractionToSeconds() {
        XCTAssertEqual(MiniPlaybackActions.seekTarget(fraction: 0.5, duration: 200), 100)
    }

    func test_seekTarget_clampsOutOfRangeFractions() {
        XCTAssertEqual(MiniPlaybackActions.seekTarget(fraction: -0.2, duration: 200), 0)
        XCTAssertEqual(MiniPlaybackActions.seekTarget(fraction: 1.5, duration: 200), 200)
    }

    func test_seekTarget_nilForNonPositiveDuration() {
        XCTAssertNil(MiniPlaybackActions.seekTarget(fraction: 0.5, duration: 0))
        XCTAssertNil(MiniPlaybackActions.seekTarget(fraction: 0.5, duration: -10))
    }
}
