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

    // MARK: - chipMaxWidth (compact chips never overlap their neighbor)

    func test_chipMaxWidth_capsToGapBeforeNextChip() {
        // Lines at 10s and 20s over a 100s/1000pt lane → 100pt apart; minus the
        // 6pt gap leaves 94pt for the first chip (below the cap).
        let width = LyricsLaneLayout.chipMaxWidth(
            forTime: 10, allTimes: [10, 20], duration: 100, contentWidth: 1000, gap: 6, cap: 140
        )
        XCTAssertEqual(width, 94, accuracy: 0.001)
    }

    func test_chipMaxWidth_clampsToCap_whenNextChipIsFarAway() {
        // 10s → 90s is 800pt apart; the cap (140) wins.
        let width = LyricsLaneLayout.chipMaxWidth(
            forTime: 10, allTimes: [10, 90], duration: 100, contentWidth: 1000, gap: 6, cap: 140
        )
        XCTAssertEqual(width, 140, accuracy: 0.001)
    }

    func test_chipMaxWidth_lastChip_usesRemainingWidth() {
        // The last chip (no later line) runs to the lane's right edge minus gap.
        let width = LyricsLaneLayout.chipMaxWidth(
            forTime: 90, allTimes: [10, 90], duration: 100, contentWidth: 1000, gap: 6, cap: 140
        )
        // pos(90) = 900; 1000 - 900 - 6 = 94.
        XCTAssertEqual(width, 94, accuracy: 0.001)
    }

    func test_chipMaxWidth_singleLine_clampsToCap() {
        // Only one line → runs to the right edge, so the cap wins.
        let width = LyricsLaneLayout.chipMaxWidth(
            forTime: 10, allTimes: [10], duration: 100, contentWidth: 1000, gap: 6, cap: 140
        )
        XCTAssertEqual(width, 140, accuracy: 0.001)
    }

    func test_chipMaxWidth_neverNegative() {
        // A later line packed right against this one yields no room → clamps to 0,
        // never a negative width.
        let width = LyricsLaneLayout.chipMaxWidth(
            forTime: 10, allTimes: [10, 10.2], duration: 100, contentWidth: 1000, gap: 6, cap: 140
        )
        XCTAssertEqual(width, 0, accuracy: 0.001)
    }
}
