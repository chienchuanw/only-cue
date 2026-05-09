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
}
