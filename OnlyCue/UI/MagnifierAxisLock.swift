import CoreGraphics

/// Pure-function helper that decides which axis "wins" when Shift is held during
/// a magnifier drag. Lives outside SwiftUI so the decision branches can be
/// unit-tested without spinning up a view host.
///
/// The lock is one-shot per drag: once `.lockedHorizontal` or `.lockedVertical`
/// is decided, it sticks for the rest of the drag, even if Shift is released
/// mid-drag. This is a deliberate UX choice — flipping axes mid-drag would be
/// surprising. The view resets `state` to `.unresolved` on `DragGesture.onEnded`.
enum MagnifierAxisLock {

    enum State: Equatable {
        case unresolved
        case unlocked
        case lockedHorizontal
        case lockedVertical
    }

    struct Resolution: Equatable {
        let nextState: State
        let effectiveX: CGFloat
        let effectiveY: CGFloat
    }

    /// Below this absolute translation (in points), the user has not moved far
    /// enough to declare axis intent — both translations pass through unchanged
    /// regardless of `isShiftHeld`, and `nextState` stays `.unresolved`.
    static let decisionThreshold: CGFloat = 10

    static func resolve(
        translationX: CGFloat,
        translationY: CGFloat,
        isShiftHeld: Bool,
        currentState: State
    ) -> Resolution {
        switch currentState {
        case .lockedHorizontal:
            return Resolution(nextState: .lockedHorizontal, effectiveX: translationX, effectiveY: 0)
        case .lockedVertical:
            return Resolution(nextState: .lockedVertical, effectiveX: 0, effectiveY: translationY)
        case .unlocked:
            return Resolution(nextState: .unlocked, effectiveX: translationX, effectiveY: translationY)
        case .unresolved:
            break
        }

        let absX = abs(translationX)
        let absY = abs(translationY)

        guard isShiftHeld else {
            return Resolution(nextState: .unlocked, effectiveX: translationX, effectiveY: translationY)
        }

        if max(absX, absY) < Self.decisionThreshold {
            return Resolution(nextState: .unresolved, effectiveX: translationX, effectiveY: translationY)
        }

        if absX >= absY {
            return Resolution(nextState: .lockedHorizontal, effectiveX: translationX, effectiveY: 0)
        } else {
            return Resolution(nextState: .lockedVertical, effectiveX: 0, effectiveY: translationY)
        }
    }
}
