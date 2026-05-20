import XCTest
@testable import OnlyCue

/// The unplaced-queue cursor. Tracks the next-up line by `LyricLine.ID` (not by
/// index — placing a line removes it from `unplacedLines`, so an index-based
/// cursor would desync).
final class LyricsAuthoringCursorTests: XCTestCase {

    private func unplaced(_ text: String) -> LyricLine { LyricLine(time: nil, text: text) }

    func test_cursor_defaultsToFirstUnplacedLine() {
        let lines = [unplaced("a"), unplaced("b")]
        let cursor = LyricsAuthoringCursor(cursorID: nil)
        XCTAssertEqual(cursor.resolvedCursorID(unplaced: lines), lines[0].id)
    }

    func test_cursor_honoursAnExplicitSelection() {
        let lines = [unplaced("a"), unplaced("b")]
        let cursor = LyricsAuthoringCursor(cursorID: lines[1].id)
        XCTAssertEqual(cursor.resolvedCursorID(unplaced: lines), lines[1].id)
    }

    func test_cursor_fallsBackWhenSelectionNoLongerUnplaced() {
        let lines = [unplaced("a"), unplaced("b")]
        let cursor = LyricsAuthoringCursor(cursorID: UUID())
        XCTAssertEqual(
            cursor.resolvedCursorID(unplaced: lines),
            lines[0].id,
            "a stale cursor falls back to the first unplaced line"
        )
    }

    func test_cursor_nilWhenQueueEmpty() {
        let cursor = LyricsAuthoringCursor(cursorID: nil)
        XCTAssertNil(cursor.resolvedCursorID(unplaced: []))
    }

    func test_advance_movesToNextUnplacedLineByIdentity() {
        let lines = [unplaced("a"), unplaced("b"), unplaced("c")]
        var cursor = LyricsAuthoringCursor(cursorID: lines[0].id)
        cursor.advance(afterPlacing: lines[0].id, remainingUnplaced: [lines[1], lines[2]])
        XCTAssertEqual(cursor.cursorID, lines[1].id)
    }

    func test_advance_nilWhenNothingLeft() {
        let lines = [unplaced("a")]
        var cursor = LyricsAuthoringCursor(cursorID: lines[0].id)
        cursor.advance(afterPlacing: lines[0].id, remainingUnplaced: [])
        XCTAssertNil(cursor.cursorID)
    }

    func test_select_setsCursorExplicitly() {
        let lines = [unplaced("a"), unplaced("b")]
        var cursor = LyricsAuthoringCursor()
        cursor.select(lines[1].id)
        XCTAssertEqual(cursor.resolvedCursorID(unplaced: lines), lines[1].id)
    }
}
