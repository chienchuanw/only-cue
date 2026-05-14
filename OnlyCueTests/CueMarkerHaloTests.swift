import XCTest
@testable import OnlyCue

/// Pins the `(isHovered, isSelected) → showHalo` dispatch used to render the
/// hover halo behind a cue marker. Selected markers suppress the halo
/// because the selected style (thicker line + larger cap) already conveys
/// focus, and stacking both reads as noisy.
final class CueMarkerHaloTests: XCTestCase {

    func test_normal_noHover_noHalo() {
        XCTAssertFalse(CueMarkerView.showHalo(isHovered: false, isSelected: false))
    }

    func test_hovered_notSelected_showsHalo() {
        XCTAssertTrue(CueMarkerView.showHalo(isHovered: true, isSelected: false))
    }

    func test_selected_notHovered_noHalo() {
        XCTAssertFalse(CueMarkerView.showHalo(isHovered: false, isSelected: true))
    }

    func test_selected_hovered_haloSuppressed() {
        XCTAssertFalse(CueMarkerView.showHalo(isHovered: true, isSelected: true))
    }
}
