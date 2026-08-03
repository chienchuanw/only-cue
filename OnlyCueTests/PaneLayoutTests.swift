import XCTest
@testable import OnlyCue

final class PaneLayoutTests: XCTestCase {

    // MARK: - Defaults

    func test_default_matchesTheShippingWidths() {
        let layout = PaneLayout.default
        XCTAssertEqual(layout.sidebarWidth, SidebarMetrics.idealWidth)
        XCTAssertFalse(layout.isSidebarCollapsed)
        XCTAssertEqual(layout.inspectorWidth, CueListInspectorMetrics.idealWidth)
        XCTAssertFalse(layout.isInspectorCollapsed)
    }

    // MARK: - Clamping

    func test_clamped_atDesignWidth_isUnchanged() {
        // 240 sidebar + 680 center + 360 inspector = 1280 (Figma 318:1311).
        let layout = PaneLayout.default
        XCTAssertEqual(layout.clamped(toAvailableWidth: 1280), layout)
    }

    func test_clamped_justInsideTheCentreFloor_isUnchanged() {
        // 1180 available: 240 sidebar + 360 inspector leaves 580 for the
        // centre, above its 560 floor — so nothing gives.
        XCTAssertEqual(
            PaneLayout.default.clamped(toAvailableWidth: 1180),
            PaneLayout.default
        )
    }

    func test_clamped_slightlyNarrow_shrinksTheInspectorFirst() {
        // 1140 available: 240 + 360 leaves 540, 20pt short of the 560 floor,
        // so the inspector gives up exactly 20 (360 -> 340) and the sidebar
        // stays put.
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 1140)
        XCTAssertEqual(clamped.inspectorWidth, 340)
        XCTAssertFalse(clamped.isInspectorCollapsed)
        XCTAssertEqual(clamped.sidebarWidth, SidebarMetrics.idealWidth)
    }

    func test_clamped_belowTheInspectorMinimum_collapsesTheInspector() {
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 1100)
        XCTAssertTrue(clamped.isInspectorCollapsed)
        // The width is retained so re-showing restores the saved value.
        XCTAssertEqual(clamped.inspectorWidth, 340)
        XCTAssertFalse(clamped.isSidebarCollapsed)
    }

    func test_clamped_veryNarrow_thenShrinksTheSidebar() {
        // 760 available: inspector collapsed leaves 760 - 240 = 520 < 560,
        // so the sidebar gives up 40pt but stays above its 240 minimum only
        // by collapsing — 240 is already the floor, so it collapses.
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 760)
        XCTAssertTrue(clamped.isInspectorCollapsed)
        XCTAssertTrue(clamped.isSidebarCollapsed)
    }

    func test_clamped_neverGrowsAPane() {
        var wide = PaneLayout.default
        wide.inspectorWidth = 340
        XCTAssertEqual(wide.clamped(toAvailableWidth: 3000).inspectorWidth, 340)
    }

    func test_clamped_isIdempotent() {
        let once = PaneLayout.default.clamped(toAvailableWidth: 1100)
        XCTAssertEqual(once.clamped(toAvailableWidth: 1100), once)
    }

    func test_clamped_zeroAvailableWidth_doesNotProduceNegativeWidths() {
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 0)
        XCTAssertGreaterThanOrEqual(clamped.sidebarWidth, 0)
        XCTAssertGreaterThanOrEqual(clamped.inspectorWidth, 0)
    }

    // MARK: - Sidebar inset (#714, spike caveat)

    func test_dividerPosition_derivesTheInsetFromTheLivePair_ratherThanHardcodingIt() {
        // The SwiftUI-reported sidebar width runs consistently under the
        // NSSplitView divider position (240<->248, 292<->300, 257<->265 in the
        // spike). The offset is derived from whatever pair is observed live,
        // never assumed to be 8 — a future SwiftUI release may change it.
        let inset = SidebarWidthBridge.inset(measuredWidth: 292, dividerPosition: 300)
        XCTAssertEqual(inset, 8)
        XCTAssertEqual(
            SidebarWidthBridge.dividerPosition(forTargetWidth: 320, inset: inset),
            328
        )
    }

    func test_dividerPosition_withNoObservedPair_appliesTheTargetUnadjusted() {
        // Before the first measurement there is no pair to derive from.
        // Applying the raw target is off by the inset for one frame, then the
        // measurement arrives and it settles — better than baking in a guess.
        XCTAssertEqual(
            SidebarWidthBridge.dividerPosition(forTargetWidth: 300, inset: nil),
            300
        )
    }

    // MARK: - Codable

    func test_roundTrip_preservesEveryField() throws {
        var layout = PaneLayout.default
        layout.sidebarWidth = 300
        layout.isInspectorCollapsed = true
        let data = try JSONEncoder().encode(layout)
        XCTAssertEqual(try JSONDecoder().decode(PaneLayout.self, from: data), layout)
    }
}
