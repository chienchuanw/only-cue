import XCTest
@testable import OnlyCue

/// Pins the editor switcher-bar spacing to its Figma spec (#552, switcher-bar
/// section of docs/design/figma-audit-2026-06-05.md). Renderer-independent
/// value pins — these are off-grid (no DS token) so a regression to a token
/// value would silently drift the bar; this fails CI deterministically.
final class EditorModeSwitcherMetricsTests: XCTestCase {

    func test_switcherMetrics_matchFigma() {
        XCTAssertEqual(EditorModeSwitcher.Metrics.trackPadding, 3)
        XCTAssertEqual(EditorModeSwitcher.Metrics.segmentGap, 5)
        XCTAssertEqual(EditorModeSwitcher.Metrics.segmentHPadding, 11)
        XCTAssertEqual(EditorModeSwitcher.Metrics.segmentVPadding, 5)
        XCTAssertEqual(EditorModeSwitcher.Metrics.iconLabelGap, 5)
        XCTAssertEqual(EditorModeSwitcher.Metrics.iconSize, 13)
    }
}
