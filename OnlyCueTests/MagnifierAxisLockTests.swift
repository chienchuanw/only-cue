import XCTest
@testable import OnlyCue

final class MagnifierAxisLockTests: XCTestCase {

    func test_noShift_returnsUnlockedPassThrough() {
        let result = MagnifierAxisLock.resolve(
            translationX: 30,
            translationY: 5,
            isShiftHeld: false,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 30)
        XCTAssertEqual(result.effectiveY, 5)
        XCTAssertEqual(result.nextState, .unlocked)
    }

    func test_noShift_belowThreshold_staysUnresolved() {
        let result = MagnifierAxisLock.resolve(
            translationX: 4,
            translationY: 2,
            isShiftHeld: false,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 4)
        XCTAssertEqual(result.effectiveY, 2)
        XCTAssertEqual(
            result.nextState,
            .unresolved,
            "sub-threshold drag-start jitter (no Shift) must NOT commit to .unlocked — Shift pressed mid-drag should still engage axis-lock"
        )
    }

    func test_shift_belowThreshold_passThroughAndStaysUnresolved() {
        let result = MagnifierAxisLock.resolve(
            translationX: 5,
            translationY: 3,
            isShiftHeld: true,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 5)
        XCTAssertEqual(result.effectiveY, 3)
        XCTAssertEqual(
            result.nextState,
            .unresolved,
            "below threshold the user has not declared intent — must stay unresolved"
        )
    }

    func test_shift_atThreshold_horizontalDominant_locksHorizontal() {
        let result = MagnifierAxisLock.resolve(
            translationX: 15,
            translationY: 4,
            isShiftHeld: true,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 15)
        XCTAssertEqual(result.effectiveY, 0, "vertical must be zeroed once horizontal is locked")
        XCTAssertEqual(result.nextState, .lockedHorizontal)
    }

    func test_shift_atThreshold_verticalDominant_locksVertical() {
        let result = MagnifierAxisLock.resolve(
            translationX: 4,
            translationY: 15,
            isShiftHeld: true,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 0, "horizontal must be zeroed once vertical is locked")
        XCTAssertEqual(result.effectiveY, 15)
        XCTAssertEqual(result.nextState, .lockedVertical)
    }

    func test_shift_alreadyLockedHorizontal_keepsLock_evenIfShiftReleased() {
        let result = MagnifierAxisLock.resolve(
            translationX: 20,
            translationY: 30,
            isShiftHeld: false,
            currentState: .lockedHorizontal
        )
        XCTAssertEqual(result.effectiveX, 20)
        XCTAssertEqual(result.effectiveY, 0, "lock is one-shot per drag — releasing Shift mid-drag must NOT release the lock")
        XCTAssertEqual(result.nextState, .lockedHorizontal)
    }

    func test_shift_alreadyLockedVertical_keepsLock() {
        let result = MagnifierAxisLock.resolve(
            translationX: 30,
            translationY: 20,
            isShiftHeld: true,
            currentState: .lockedVertical
        )
        XCTAssertEqual(result.effectiveX, 0)
        XCTAssertEqual(result.effectiveY, 20)
        XCTAssertEqual(result.nextState, .lockedVertical)
    }

    func test_unlocked_passThroughWithShiftIgnored() {
        let result = MagnifierAxisLock.resolve(
            translationX: 25,
            translationY: 8,
            isShiftHeld: true,
            currentState: .unlocked
        )
        XCTAssertEqual(result.effectiveX, 25)
        XCTAssertEqual(
            result.effectiveY,
            8,
            "once .unlocked, the drag stays unlocked for the rest of the gesture even if Shift is held mid-drag"
        )
        XCTAssertEqual(result.nextState, .unlocked)
    }

    func test_shift_exactMagnitudeTie_locksHorizontal() {
        let result = MagnifierAxisLock.resolve(
            translationX: 12,
            translationY: 12,
            isShiftHeld: true,
            currentState: .unresolved
        )
        XCTAssertEqual(result.nextState, .lockedHorizontal, "tie breaks toward horizontal")
        XCTAssertEqual(result.effectiveX, 12)
        XCTAssertEqual(result.effectiveY, 0)
    }
}
