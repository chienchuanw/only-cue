import XCTest
import CoreGraphics
@testable import OnlyCue

/// Pure x↔time math for placing and dragging chips on the lyric lane.
final class LyricsLaneInteractionTests: XCTestCase {

    func test_mediaTime_atLeftEdgeIsZero() {
        XCTAssertEqual(LyricsLaneInteraction.mediaTime(forX: 0, width: 200, duration: 100), 0)
    }

    func test_mediaTime_atMidpointIsHalfDuration() {
        XCTAssertEqual(LyricsLaneInteraction.mediaTime(forX: 100, width: 200, duration: 100), 50)
    }

    func test_mediaTime_clampsBeyondEnds() {
        XCTAssertEqual(LyricsLaneInteraction.mediaTime(forX: -40, width: 200, duration: 100), 0)
        XCTAssertEqual(LyricsLaneInteraction.mediaTime(forX: 999, width: 200, duration: 100), 100)
    }

    func test_mediaTime_zeroWidthIsZero() {
        XCTAssertEqual(LyricsLaneInteraction.mediaTime(forX: 50, width: 0, duration: 100), 0)
    }

    func test_draggedMediaTime_appliesPixelDelta() {
        let result = LyricsLaneInteraction.draggedMediaTime(
            fromMediaTime: 50, dx: 20, width: 200, duration: 100
        )
        XCTAssertEqual(result, 60)
    }

    func test_draggedMediaTime_clampsToDuration() {
        let result = LyricsLaneInteraction.draggedMediaTime(
            fromMediaTime: 95, dx: 200, width: 200, duration: 100
        )
        XCTAssertEqual(result, 100)
    }

    func test_draggedMediaTime_clampsToZero() {
        let result = LyricsLaneInteraction.draggedMediaTime(
            fromMediaTime: 5, dx: -200, width: 200, duration: 100
        )
        XCTAssertEqual(result, 0)
    }
}
