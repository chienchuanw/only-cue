import XCTest
@testable import OnlyCue

final class MiniPlaybackActionsTests: XCTestCase {

    func test_rateChangeMapping() {
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateUp), .up)
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateDown), .down)
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateReset), .reset)
        XCTAssertNil(MiniPlaybackActions.rateChange(for: .playPause))
    }
}
