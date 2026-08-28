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

    /// Figma `77:43` `color-stripe`: 5 pt wide, matching the cue list's type
    /// stripe so the two colour idioms read as the same mechanism (#782).
    func test_colorStripeWidthMatchesTheCueListTypeStripe() {
        XCTAssertEqual(ItemRowMetrics.colorStripeWidth, 5)
        XCTAssertEqual(ItemRowMetrics.colorStripeWidth, CueListLayout.typeStripeWidth)
    }

    /// Figma `77:43` `paddingLeft` = 13: the stripe plus `DS.Space.sm` of
    /// breathing room, so the colour never crowds the kind icon.
    func test_colorGutterIsTheStripePlusOneSpaceUnit() {
        XCTAssertEqual(ItemRowMetrics.colorGutter, 13)
    }
}
