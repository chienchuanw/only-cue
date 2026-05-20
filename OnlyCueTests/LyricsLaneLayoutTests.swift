import XCTest
@testable import OnlyCue

/// `LyricsLaneLayout` decides whether the lane renders readable text or
/// collapses to ticks, based on how much horizontal space each line gets.
final class LyricsLaneLayoutTests: XCTestCase {

    func test_collapsesToTicks_whenPerLineWidthBelowThreshold() {
        // 60 lines across 600pt content -> 10pt each -> below the 40pt threshold.
        XCTAssertTrue(LyricsLaneLayout.shouldCollapseToTicks(lineCount: 60, contentWidth: 600))
    }

    func test_rendersText_whenPerLineWidthAboveThreshold() {
        // 5 lines across 600pt -> 120pt each -> readable.
        XCTAssertFalse(LyricsLaneLayout.shouldCollapseToTicks(lineCount: 5, contentWidth: 600))
    }

    func test_noCollapse_whenNoLines() {
        XCTAssertFalse(LyricsLaneLayout.shouldCollapseToTicks(lineCount: 0, contentWidth: 600))
    }

    func test_collapses_whenContentWidthIsZero() {
        XCTAssertTrue(LyricsLaneLayout.shouldCollapseToTicks(lineCount: 3, contentWidth: 0))
    }
}
