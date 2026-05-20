import XCTest
@testable import OnlyCue

final class LyricsTapAlongTests: XCTestCase {

    private func lines(_ texts: [String]) -> [LyricLine] {
        texts.map { LyricLine(time: 0, text: $0) }
    }

    /// Mirrors the draft re-sort by `time` ascending (unplaced/nil sorts first).
    private func resorted(_ lines: [LyricLine]) -> [LyricLine] {
        lines.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
    }

    func test_stamping_setsSongRelativeTime_andAdvancesCursor() {
        let rows = lines(["a", "b", "c"])
        var state = LyricsTapAlong(lines: rows)
        let result = state.stamping(rows, playhead: 12, offsetSeconds: 0)
        XCTAssertEqual(result[0].time, 12)
        XCTAssertEqual(state.cursorID, rows[1].id)
    }

    func test_stamping_subtractsOffsetSoTimeIsSongRelative() {
        let rows = lines(["a"])
        var state = LyricsTapAlong(lines: rows)
        let result = state.stamping(rows, playhead: 122, offsetSeconds: 60)
        XCTAssertEqual(result[0].time, 62, "stored time stays on the song clock")
    }

    func test_stamping_clampsNegativeResultToZero() {
        let rows = lines(["a"])
        var state = LyricsTapAlong(lines: rows)
        let result = state.stamping(rows, playhead: 5, offsetSeconds: 60)
        XCTAssertEqual(result[0].time, 0)
    }

    func test_stamping_pastLastRow_isNoOp() {
        let rows = lines(["a"])
        var state = LyricsTapAlong(lines: rows)
        var draft = state.stamping(rows, playhead: 1, offsetSeconds: 0)   // cursor past end
        XCTAssertNil(state.cursorID)
        let snapshot = draft
        draft = state.stamping(draft, playhead: 9, offsetSeconds: 0)      // no-op
        XCTAssertEqual(draft, snapshot)
    }

    func test_stepBack_movesCursorUpWithoutStamping() {
        let rows = lines(["a", "b"])
        var state = LyricsTapAlong(lines: rows)
        _ = state.stamping(rows, playhead: 3, offsetSeconds: 0)           // cursor -> "b"
        XCTAssertEqual(state.cursorID, rows[1].id)
        state.stepBack()
        XCTAssertEqual(state.cursorID, rows[0].id)
    }

    func test_stepBack_atFirstRow_isNoOp() {
        var state = LyricsTapAlong(lines: lines(["a"]))
        state.stepBack()
        XCTAssertEqual(state.position, 0)
    }

    func test_reStamp_overwritesAfterStepBack() {
        let rows = lines(["a", "b"])
        var state = LyricsTapAlong(lines: rows)
        var draft = state.stamping(rows, playhead: 3, offsetSeconds: 0)
        state.stepBack()
        draft = state.stamping(draft, playhead: 5, offsetSeconds: 0)
        XCTAssertEqual(draft[0].time, 5, "re-tapping overwrites the row's time")
    }

    /// Regression: the draft is re-sorted by `time` between taps (as
    /// `commit()` -> `Lyrics.init` does). The cursor must keep tracking the
    /// correct row by identity, not by position.
    func test_stamping_survivesResortBetweenTaps() {
        let rows = lines(["one", "two", "three"])   // all time 0
        var state = LyricsTapAlong(lines: rows)

        // Tap 1: stamp "one" at 5, then re-sort (moves "one" to the end).
        var draft = resorted(state.stamping(rows, playhead: 5, offsetSeconds: 0))
        XCTAssertEqual(state.cursorID, rows[1].id, "cursor still points at 'two' by identity")

        // Tap 2: stamp "two" at 10 in the reordered draft.
        draft = state.stamping(draft, playhead: 10, offsetSeconds: 0)
        let stampedTwo = draft.first { $0.id == rows[1].id }?.time
        XCTAssertEqual(stampedTwo, 10, "the correct row was stamped despite the re-sort")
        XCTAssertEqual(state.cursorID, rows[2].id)
    }
}
