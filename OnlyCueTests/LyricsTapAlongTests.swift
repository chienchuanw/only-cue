import XCTest
@testable import OnlyCue

final class LyricsTapAlongTests: XCTestCase {

    private func lines(_ texts: [String]) -> [LyricLine] {
        texts.map { LyricLine(time: 0, text: $0) }
    }

    func test_stamping_setsSongRelativeTime_andAdvancesCursor() {
        var state = LyricsTapAlong()
        let result = state.stamping(lines(["a", "b", "c"]), playhead: 12, offsetSeconds: 0)
        XCTAssertEqual(result[0].time, 12)
        XCTAssertEqual(state.cursor, 1)
    }

    func test_stamping_subtractsOffsetSoTimeIsSongRelative() {
        var state = LyricsTapAlong()
        let result = state.stamping(lines(["a"]), playhead: 122, offsetSeconds: 60)
        XCTAssertEqual(result[0].time, 62, "stored time stays on the song clock")
    }

    func test_stamping_clampsNegativeResultToZero() {
        var state = LyricsTapAlong()
        let result = state.stamping(lines(["a"]), playhead: 5, offsetSeconds: 60)
        XCTAssertEqual(result[0].time, 0)
    }

    func test_stamping_pastLastRow_isNoOp() {
        var state = LyricsTapAlong()
        var rows = lines(["a"])
        rows = state.stamping(rows, playhead: 1, offsetSeconds: 0)   // cursor -> 1 (past last)
        let snapshot = rows
        rows = state.stamping(rows, playhead: 9, offsetSeconds: 0)   // no-op
        XCTAssertEqual(rows, snapshot)
        XCTAssertEqual(state.cursor, 1)
    }

    func test_stepBack_movesCursorUpWithoutStamping() {
        var state = LyricsTapAlong()
        let rows = state.stamping(lines(["a", "b"]), playhead: 3, offsetSeconds: 0)   // cursor -> 1
        state.stepBack()
        XCTAssertEqual(state.cursor, 0)
        XCTAssertEqual(rows[1].time, 0, "step-back does not stamp")
    }

    func test_stepBack_atFirstRow_isNoOp() {
        var state = LyricsTapAlong()
        state.stepBack()
        XCTAssertEqual(state.cursor, 0)
    }

    func test_reStamp_overwritesAfterStepBack() {
        var state = LyricsTapAlong()
        var rows = lines(["a", "b"])
        rows = state.stamping(rows, playhead: 3, offsetSeconds: 0)
        state.stepBack()
        rows = state.stamping(rows, playhead: 5, offsetSeconds: 0)
        XCTAssertEqual(rows[0].time, 5, "re-tapping overwrites the row's time")
    }
}
