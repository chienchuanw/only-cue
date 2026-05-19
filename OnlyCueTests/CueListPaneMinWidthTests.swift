import XCTest
@testable import OnlyCue

/// Behavioral regression for issue #297 — the `NSSplitView` constraint-update
/// recursion when dragging the main-pane / cue-list `.inspector` divider.
///
/// Root cause: after `b8dfae0` removed the isolating inner `VSplitView`, the
/// cue-list content's intrinsic minimum width is reported straight to the
/// hosting view the outer `NSSplitView` measures. The header / `CueRowView`
/// pinned the Time/Cue#/Fade columns with rigid `.frame(width:)`, so the
/// pane's minimum width floor (column defaults + spacing + horizontal
/// chrome) sat *above* the inspector column minimum (240). When the splitter
/// drives the pane toward 240 the content keeps demanding more, the hosting
/// view re-reports a larger min, the splitter re-lays out — the bistable
/// `400 -> 240` snap captured on the issue — recursing until AppKit asserts
/// `NSGenericException: ... more Update Constraints passes than there are
/// views`.
///
/// The invariant that makes the loop impossible: the cue-list content's
/// guaranteed-compressible minimum width must never exceed the inspector
/// column minimum. This is the deterministic, CI-stable guard
/// (`SplitDividerCrashUITests` is the behavioural guard but is hit-test
/// fragile headless). If a future change reintroduces a rigid floor wider
/// than the column minimum, this fails fast.
final class CueListPaneMinWidthTests: XCTestCase {

    func test_headerMinimumWidth_doesNotExceedInspectorColumnMinimum() {
        XCTAssertLessThanOrEqual(
            CueListPane.headerMinimumWidth,
            CueListInspectorMetrics.minWidth,
            """
            Cue-list header floor (\(CueListPane.headerMinimumWidth)) exceeds the \
            inspector column minimum (\(CueListInspectorMetrics.minWidth)). The \
            outer NSSplitView cannot drive the pane to its 240 minimum without the \
            content demanding more — the issue #297 constraint loop.
            """
        )
    }

    func test_columnsCompressToRangeMinimums_notFixedDefaults() {
        // The fix's mechanism: the three fixed columns must be able to
        // compress to their range lower bounds under width pressure, not be
        // pinned at their (wider) stored/default widths. Pin the budget so a
        // regression to `.frame(width:)` is caught at the source.
        let compressibleFloor =
            CueListColumnWidths.timeRange.lowerBound
            + CueListColumnWidths.numberRange.lowerBound
            + CueListColumnWidths.fadeRange.lowerBound
        let defaultsFloor =
            CueListColumnWidths.timeDefault
            + CueListColumnWidths.numberDefault
            + CueListColumnWidths.fadeDefault
        XCTAssertLessThan(
            compressibleFloor,
            defaultsFloor,
            "range minimums must be strictly narrower than defaults for compression to buy headroom"
        )
        XCTAssertLessThanOrEqual(
            compressibleFloor + CueListPane.headerHorizontalChrome,
            CueListInspectorMetrics.minWidth,
            "fully-compressed header must fit within the inspector column minimum"
        )
    }
}
