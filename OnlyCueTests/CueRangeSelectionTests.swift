import XCTest
@testable import OnlyCue

/// #790 — ⇧-click selects the inclusive range between the anchor and the
/// clicked row.
///
/// The range is resolved against the **displayed** id order handed in by the
/// pane, never against `Cue.ID` or cue time: the user is pointing at rows on
/// screen, so "between" can only mean between them as drawn. Keeping that a
/// pure function over `[Cue.ID]` is what makes it testable at all — and it is
/// why a future row-hiding filter needs no change here, only a shorter array.
final class CueRangeSelectionTests: XCTestCase {

    private let rows = (0..<10).map { _ in UUID() }

    func test_forwardRange_isInclusiveOfBothEnds() {
        XCTAssertEqual(
            CueRangeSelection.range(in: rows, from: rows[2], to: rows[8]),
            Set(rows[2...8])
        )
    }

    /// Dragging the same range out backwards must land on the same rows —
    /// otherwise ⇧-clicking above the anchor would select nothing.
    func test_backwardRange_selectsTheSameRowsAsForward() {
        XCTAssertEqual(
            CueRangeSelection.range(in: rows, from: rows[8], to: rows[2]),
            CueRangeSelection.range(in: rows, from: rows[2], to: rows[8])
        )
    }

    func test_anchorEqualsTarget_selectsOnlyThatRow() {
        XCTAssertEqual(
            CueRangeSelection.range(in: rows, from: rows[4], to: rows[4]),
            [rows[4]]
        )
    }

    /// Nothing has been selected yet, so there is no origin to range from. The
    /// click still has to do something, and selecting what was clicked is the
    /// only answer that does not surprise.
    func test_withoutAnAnchor_selectsOnlyTheClickedRow() {
        XCTAssertEqual(
            CueRangeSelection.range(in: rows, from: nil, to: rows[6]),
            [rows[6]]
        )
    }

    /// The anchor row was selected, then stopped being displayed — a filter, or
    /// the cue was deleted from another pane. A stale anchor must not range from
    /// a phantom position; it degrades to "select the clicked row", which also
    /// re-anchors at the caller.
    func test_anchorNoLongerDisplayed_selectsOnlyTheClickedRow() {
        XCTAssertEqual(
            CueRangeSelection.range(in: rows, from: UUID(), to: rows[6]),
            [rows[6]]
        )
    }

    /// Defensive: the caller clicked a row, so it is displayed by construction.
    /// Defined rather than left to a crash-on-nil index.
    func test_targetNotDisplayed_stillSelectsTheClickedRow() {
        let orphan = UUID()
        XCTAssertEqual(
            CueRangeSelection.range(in: rows, from: rows[1], to: orphan),
            [orphan]
        )
    }

    /// The point of taking the displayed array rather than sorting ids: the
    /// rows here are deliberately in an order that has nothing to do with the
    /// UUIDs' own ordering, and the range must follow the array.
    func test_rangeFollowsDisplayedOrder_notIdOrder() {
        let shuffled = [rows[7], rows[1], rows[9], rows[3], rows[0]]
        XCTAssertEqual(
            CueRangeSelection.range(in: shuffled, from: rows[1], to: rows[3]),
            [rows[1], rows[9], rows[3]]
        )
    }

    func test_emptyList_selectsOnlyTheClickedRow() {
        let orphan = UUID()
        XCTAssertEqual(CueRangeSelection.range(in: [], from: nil, to: orphan), [orphan])
    }
}
