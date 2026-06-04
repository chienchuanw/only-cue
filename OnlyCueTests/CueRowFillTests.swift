import XCTest
import SwiftUI
@testable import OnlyCue

final class CueRowFillTests: XCTestCase {

    private let tint = Color.red
    private let selection = Color.gray

    /// Figma 318:1228: unselected rows are clean — no per-row cue-type tint.
    func test_unselectedRow_isClear() {
        let fill = CueRowFill.color(
            isSelected: false,
            isReadOnly: false,
            isCurrent: false,
            tint: tint,
            selection: selection
        )
        XCTAssertEqual(fill, .clear)
    }

    /// The selected row carries its cue-type tint (the only chroma — the tint
    /// is reserved for selection, not painted on every row).
    func test_selectedRow_carriesCueTypeTint() {
        let fill = CueRowFill.color(
            isSelected: true,
            isReadOnly: false,
            isCurrent: false,
            tint: tint,
            selection: selection
        )
        XCTAssertEqual(fill, tint)
    }

    /// Show mode (read-only): the cue currently at the playhead keeps the
    /// achromatic selection highlight.
    func test_showMode_currentCue_usesSelectionHighlight() {
        let fill = CueRowFill.color(
            isSelected: false,
            isReadOnly: true,
            isCurrent: true,
            tint: tint,
            selection: selection
        )
        XCTAssertEqual(fill, selection)
    }

    /// In Show mode the current-cue highlight wins over a stale selection.
    func test_showMode_currentAndSelected_prefersCurrentHighlight() {
        let fill = CueRowFill.color(
            isSelected: true,
            isReadOnly: true,
            isCurrent: true,
            tint: tint,
            selection: selection
        )
        XCTAssertEqual(fill, selection)
    }

    /// Show mode, neither current nor selected: still clean.
    func test_showMode_idleRow_isClear() {
        let fill = CueRowFill.color(
            isSelected: false,
            isReadOnly: true,
            isCurrent: false,
            tint: tint,
            selection: selection
        )
        XCTAssertEqual(fill, .clear)
    }
}
