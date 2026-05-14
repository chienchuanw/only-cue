import XCTest
import SwiftUI
@testable import OnlyCue

final class ColumnResizeHandleTests: XCTestCase {

    /// The handle must initialize with a binding + range and be constructible
    /// from the same primitives the header uses. If a future refactor changes
    /// the surface (e.g. requires a custom cursor or label) this catches it.
    func test_columnResizeHandle_initializer_takesBindingAndRange() {
        var width: CGFloat = 100
        let binding = Binding(get: { width }, set: { width = $0 })
        let handle = ColumnResizeHandle(width: binding, range: 64...180)
        XCTAssertNotNil(handle.body)
    }

    /// The static `apply(delta:start:range:)` helper drives the drag math —
    /// pure function, exhaustively tested so the SwiftUI gesture stays a thin
    /// shell over verified logic.
    func test_apply_clampsBelowMin() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: -500, start: 100, range: 64...180),
            64
        )
    }

    func test_apply_clampsAboveMax() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: 500, start: 100, range: 64...180),
            180
        )
    }

    func test_apply_addsDeltaWithinRange() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: 20, start: 100, range: 64...180),
            120
        )
    }

    func test_apply_negativeDeltaWithinRange() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: -10, start: 100, range: 64...180),
            90
        )
    }

    /// Regression for #269: writing to the binding on every drag tick even
    /// when the value is unchanged triggers @AppStorage notifications that
    /// feed into NSSplitView layout invalidation. The drag handler must
    /// skip no-op writes so a zero-translation gesture activation cannot
    /// drive constraint-update recursion.
    func test_writeIfChanged_skipsWhenValueEqual() {
        var writes = 0
        let binding = Binding<CGFloat>(
            get: { 100 },
            set: { _ in writes += 1 }
        )
        ColumnResizeHandle.writeIfChanged(binding, to: 100)
        XCTAssertEqual(writes, 0, "Equal values must not invoke the setter")
    }

    func test_writeIfChanged_writesWhenValueDiffers() {
        var stored: CGFloat = 100
        var writes = 0
        let binding = Binding<CGFloat>(
            get: { stored },
            set: { stored = $0; writes += 1 }
        )
        ColumnResizeHandle.writeIfChanged(binding, to: 120)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(stored, 120)
    }
}
