import XCTest
@testable import OnlyCue

/// #763 — auto-fill only the nil `cueNumber`s of a MediaItem, integer-preferring,
/// preserving user-entered numbers. Pure-function oracle (see the approved spec §4).
final class CueNumberAutoFillTests: XCTestCase {

    /// Cues are built in time order; `number == nil` marks a cue to auto-fill.
    private func cues(_ numbers: [Double?]) -> [Cue] {
        numbers.enumerated().map { index, number in
            Cue(
                id: UUID(),
                typeID: UUID(),
                cueNumber: number,
                name: "Cue \(index)",
                time: TimeInterval(index),
                notes: "",
                fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
            )
        }
    }

    /// Resolve the assigned number for the cue at `index`, failing the test if absent.
    private func assigned(_ result: [Cue.ID: Double], _ cues: [Cue], _ index: Int) -> Double? {
        result[cues[index].id]
    }

    func test_singleGap_fillsInteger() {
        let list = cues([1, nil, 3])
        let result = CueNumberAutoFill.assignments(for: list)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(assigned(result, list, 1), 2)
    }

    func test_twoGaps_fillConsecutiveIntegers() {
        let list = cues([1, nil, nil, 4])
        let result = CueNumberAutoFill.assignments(for: list)
        XCTAssertEqual(assigned(result, list, 1), 2)
        XCTAssertEqual(assigned(result, list, 2), 3)
    }

    func test_noIntegerRoom_fillsFractionalFromLowerBound() {
        let list = cues([1, nil, 2])
        let result = CueNumberAutoFill.assignments(for: list)
        XCTAssertEqual(assigned(result, list, 1) ?? 0, 1.1, accuracy: 0.0001)
    }

    func test_allNil_numbersFromOne() {
        let list = cues([nil, nil, nil])
        let result = CueNumberAutoFill.assignments(for: list)
        XCTAssertEqual(assigned(result, list, 0), 1)
        XCTAssertEqual(assigned(result, list, 1), 2)
        XCTAssertEqual(assigned(result, list, 2), 3)
    }

    func test_leadingNil_startsFromOneBelowUpper() {
        let list = cues([nil, 5])
        let result = CueNumberAutoFill.assignments(for: list)
        XCTAssertEqual(assigned(result, list, 0), 1)
    }

    func test_collisionWithinBounds_stepsFractional() {
        let list = cues([3, nil, nil, 4])
        let result = CueNumberAutoFill.assignments(for: list)
        XCTAssertEqual(assigned(result, list, 1) ?? 0, 3.1, accuracy: 0.0001)
        XCTAssertEqual(assigned(result, list, 2) ?? 0, 3.2, accuracy: 0.0001)
    }

    func test_preservesExistingNumbers_onlyNilCuesAssigned() {
        let list = cues([1, nil, 3])
        let result = CueNumberAutoFill.assignments(for: list)
        XCTAssertNil(result[list[0].id])
        XCTAssertNil(result[list[2].id])
    }

    func test_smallGap_stillFillsWhenRoomExists() {
        // A 0.05-wide gap has no whole number but a free thousandth (e.g. 1.025).
        let list = cues([1, nil, 1.05])
        let filled = CueNumberAutoFill.assignments(for: list)[list[1].id] ?? 0
        XCTAssertGreaterThan(filled, 1)
        XCTAssertLessThan(filled, 1.05)
    }

    func test_subGridGap_leavesCueUnnumbered_neverDuplicates() {
        // No representable thousandth strictly between 1.000 and 1.001 → cannot fill.
        let list = cues([1, 1.001, nil])   // nil sits after, but bounded tight elsewhere
        let tight = cues([1, nil, 1.001])
        XCTAssertNil(CueNumberAutoFill.assignments(for: tight)[tight[1].id],
                     "must not fabricate a duplicate of the existing 1.001")
        // Sanity: the loose variant (nil at the end, open upper) still fills.
        XCTAssertNotNil(CueNumberAutoFill.assignments(for: list)[list[2].id])
    }

    func test_leadingNilBeforeSubOneUpper_neverZeroOrNegative() {
        // base 0, upper 0.0004 → no value >= 0.001 fits; leave nil rather than emit 0.0.
        let list = cues([nil, 0.0004])
        XCTAssertNil(CueNumberAutoFill.assignments(for: list)[list[0].id])
    }

    func test_numbersRunningBackwardsInTime_leaveUnfillableNil() {
        // Non-monotonic: no value strictly between lower 10 and upper 5.
        let list = cues([10, nil, 5])
        XCTAssertNil(CueNumberAutoFill.assignments(for: list)[list[1].id])
    }

    func test_allNumbered_noAssignments() {
        let result = CueNumberAutoFill.assignments(for: cues([1, 2, 3]))
        XCTAssertTrue(result.isEmpty)
    }

    func test_empty_noAssignments() {
        XCTAssertTrue(CueNumberAutoFill.assignments(for: []).isEmpty)
    }
}
