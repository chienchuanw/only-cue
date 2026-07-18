import XCTest
import SwiftUI
@testable import OnlyCue

final class CueRowFillTests: XCTestCase {

    private let tint = Color.red
    private let selection = Color.gray

    /// Figma 318:1228: unselected, non-current rows are clean — no per-row tint.
    func test_idleRow_isClear() {
        let fill = CueRowFill.color(isSelected: false, isCurrent: false, tint: tint, selection: selection)
        XCTAssertEqual(fill, .clear)
    }

    /// The selected row carries its cue-type tint (the reserved chroma).
    func test_selectedRow_carriesCueTypeTint() {
        let fill = CueRowFill.color(isSelected: true, isCurrent: false, tint: tint, selection: selection)
        XCTAssertEqual(fill, tint)
    }

    /// #679: a selected cue with NO type color (tint nil) falls back to the
    /// achromatic selection highlight — otherwise, now that the blue system
    /// highlight is gone, an uncolored selected row would show nothing at all.
    func test_selectedRow_withoutTint_fallsBackToSelectionHighlight() {
        let fill = CueRowFill.color(isSelected: true, isCurrent: false, tint: nil, selection: selection)
        XCTAssertEqual(fill, selection)
    }

    /// #671: the cue at the playhead gets the achromatic highlight in ANY mode
    /// (previously Show-mode only) — the playhead's current section.
    func test_currentCue_usesSelectionHighlight() {
        let fill = CueRowFill.color(isSelected: false, isCurrent: true, tint: tint, selection: selection)
        XCTAssertEqual(fill, selection)
    }

    /// The current-cue highlight wins over the manual selection tint (#671): the
    /// same row being both shows the playhead highlight.
    func test_currentAndSelected_prefersCurrentHighlight() {
        let fill = CueRowFill.color(isSelected: true, isCurrent: true, tint: tint, selection: selection)
        XCTAssertEqual(fill, selection)
    }
}
