import SwiftUI
import XCTest
@testable import OnlyCue

/// Pins the dispatch from `isSelected: Bool` to the `CueMarkerView.MarkerStyle`
/// values used to render normal vs. selected cue markers on the waveform. The
/// selected style emphasizes the marker via a thicker line and a larger pin
/// badge; the type color is unchanged (the cue's CuePointType color carries
/// identity, not selection).
final class CueMarkerStyleTests: XCTestCase {

    func test_unselected_returnsNormalStyle() {
        let style = CueMarkerView.MarkerStyle.style(isSelected: false)
        XCTAssertEqual(style.lineWidth, 2)
        XCTAssertEqual(style.pinWidth, 18)
        XCTAssertEqual(style.pinHeight, 20)
    }

    func test_selected_returnsSelectedStyle() {
        let style = CueMarkerView.MarkerStyle.style(isSelected: true)
        XCTAssertEqual(style.lineWidth, 3)
        XCTAssertEqual(style.pinWidth, 22)
        XCTAssertEqual(style.pinHeight, 24)
    }

    func test_selectedStyle_emphasizesOverNormal() {
        let normal = CueMarkerView.MarkerStyle.style(isSelected: false)
        let selected = CueMarkerView.MarkerStyle.style(isSelected: true)
        XCTAssertGreaterThan(selected.lineWidth, normal.lineWidth)
        XCTAssertGreaterThan(selected.pinWidth, normal.pinWidth)
        XCTAssertGreaterThan(selected.pinHeight, normal.pinHeight)
    }

    // MARK: - Drag hit zone (#534)

    func test_draggableWidth_coversVisiblePin_forEasyGrab() {
        // The grab zone must be at least as wide as the visible pin, so a press
        // anywhere on the pin (including its edges) starts a marker drag instead
        // of falling through to the full-bleed seek surface below (#534).
        for selected in [false, true] {
            let pin = CueMarkerView.MarkerStyle.style(isSelected: selected).pinWidth
            XCTAssertGreaterThanOrEqual(
                CueMarkerView.draggableWidth(isSelected: selected),
                pin,
                "marker grab zone must cover its visible pin (isSelected=\(selected))"
            )
        }
    }

    // MARK: - Number color contrast (Figma #1f1c1a on bright fills, white on dark)

    func test_numberColor_lightFill_isDark() {
        XCTAssertEqual(CueMarkerView.numberColor(forHex: "#FFD400"), Color(red: 0.122, green: 0.110, blue: 0.102))
    }

    func test_numberColor_darkFill_isWhite() {
        XCTAssertEqual(CueMarkerView.numberColor(forHex: "#1A1340"), .white)
    }

    func test_numberColor_nilHex_defaultsToDark() {
        XCTAssertEqual(CueMarkerView.numberColor(forHex: nil), Color(red: 0.122, green: 0.110, blue: 0.102))
    }
}
