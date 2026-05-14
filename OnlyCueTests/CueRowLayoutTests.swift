import XCTest
import SwiftUI
@testable import OnlyCue

final class CueRowLayoutTests: XCTestCase {

    /// Pins the new initializer surface: `CueRowView` no longer takes an
    /// `index:` parameter (the position-index column was removed). The
    /// addition of explicit width parameters is what column resizing
    /// stores in `@AppStorage` and threads through both the header and
    /// every row so they stay aligned during drag.
    func test_cueRowView_initializer_takesCueColorAndWidths() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 12.5,
            name: "Verse",
            time: 12.345,
            notes: "",
            fadeTime: .zero
        )
        let view = CueRowView(
            cue: cue,
            resolvedColorHex: "#FF8800",
            timeColumnWidth: CueListColumnWidths.timeDefault,
            numberColumnWidth: CueListColumnWidths.numberDefault
        )
        XCTAssertNotNil(view.body)
    }

    /// Sanity check on the shared layout constants that still live on
    /// `CueListLayout`: row tint stays subtle enough to keep text legible.
    /// Time/Number widths now live on `CueListColumnWidths`.
    func test_cueListLayout_constants_areSane() {
        XCTAssertGreaterThan(CueListLayout.rowHorizontalSpacing, 0)
        XCTAssertGreaterThan(CueListLayout.rowTintOpacity, 0)
        XCTAssertLessThan(CueListLayout.rowTintOpacity, 0.5)
        XCTAssertGreaterThan(CueListColumnWidths.timeDefault, 0)
        XCTAssertGreaterThan(CueListColumnWidths.numberDefault, 0)
    }
}
