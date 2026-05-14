import XCTest
import SwiftUI
@testable import OnlyCue

final class CueRowLayoutTests: XCTestCase {

    /// Pins the new initializer surface: `CueRowView` no longer takes an
    /// `index:` parameter (the position-index column was removed). If a
    /// future refactor reintroduces a leading index, this test catches it.
    func test_cueRowView_initializer_takesCueAndOptionalColor() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 12.5,
            name: "Verse",
            time: 12.345,
            notes: "",
            fadeTime: .zero
        )
        let view = CueRowView(cue: cue, resolvedColorHex: "#FF8800")
        XCTAssertNotNil(view.body)
    }

    /// Sanity check on the shared layout constants: row tint stays subtle
    /// enough to keep text legible, and column widths remain non-zero.
    func test_cueListLayout_constants_areSane() {
        XCTAssertGreaterThan(CueListLayout.timeColumnWidth, 0)
        XCTAssertGreaterThan(CueListLayout.numberColumnWidth, 0)
        XCTAssertGreaterThan(CueListLayout.rowHorizontalSpacing, 0)
        XCTAssertGreaterThan(CueListLayout.rowTintOpacity, 0)
        XCTAssertLessThan(CueListLayout.rowTintOpacity, 0.5)
    }
}
