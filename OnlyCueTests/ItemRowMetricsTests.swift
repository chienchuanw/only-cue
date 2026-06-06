import XCTest
@testable import OnlyCue

/// Pure metrics for the sidebar media row, pinned to Figma 318:1238 /
/// component set 77:43. Keeping these as plain values (mirroring CueRowFill /
/// PreviewLayout) gives the single-line layout a renderer-independent gate.
final class ItemRowMetricsTests: XCTestCase {

    /// Figma 318:1238: the leading kind icon is a 14×14 glyph.
    func test_iconSizeMatchesFigma() {
        XCTAssertEqual(ItemRowMetrics.iconSize, 14)
    }

    /// Figma duration is Roboto Mono 10 (text-tertiary).
    func test_durationFontSizeMatchesFigma() {
        XCTAssertEqual(ItemRowMetrics.durationFontSize, 10)
    }

    /// At rest the edit pencil is invisible (Hovered=False), but it stays in
    /// the view tree at opacity 0 so its AX identifier remains reachable.
    func test_pencilHiddenAtRest() {
        XCTAssertEqual(ItemRowMetrics.pencilOpacity(isHovered: false), 0)
    }

    /// On hover the pencil fades fully in (Hovered=True).
    func test_pencilVisibleOnHover() {
        XCTAssertEqual(ItemRowMetrics.pencilOpacity(isHovered: true), 1)
    }
}
