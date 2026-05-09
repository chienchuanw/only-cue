import XCTest
@testable import OnlyCue

/// Pins the dispatch from `isSelected: Bool` to the `CueMarkerView.MarkerStyle`
/// values used to render normal vs. selected cue markers on the waveform. The
/// selected style emphasizes the marker via thicker line and larger cap; the
/// type color is unchanged (the cue's CuePointType color carries identity, not
/// selection).
final class CueMarkerStyleTests: XCTestCase {

    func test_unselected_returnsNormalStyle() {
        let style = CueMarkerView.MarkerStyle.style(isSelected: false)
        XCTAssertEqual(style.lineWidth, 2)
        XCTAssertEqual(style.capWidth, 10)
        XCTAssertEqual(style.capHeight, 8)
    }

    func test_selected_returnsSelectedStyle() {
        let style = CueMarkerView.MarkerStyle.style(isSelected: true)
        XCTAssertEqual(style.lineWidth, 3)
        XCTAssertEqual(style.capWidth, 14)
        XCTAssertEqual(style.capHeight, 12)
    }

    func test_selectedStyle_emphasizesOverNormal() {
        let normal = CueMarkerView.MarkerStyle.style(isSelected: false)
        let selected = CueMarkerView.MarkerStyle.style(isSelected: true)
        XCTAssertGreaterThan(selected.lineWidth, normal.lineWidth)
        XCTAssertGreaterThan(selected.capWidth, normal.capWidth)
        XCTAssertGreaterThan(selected.capHeight, normal.capHeight)
    }
}
