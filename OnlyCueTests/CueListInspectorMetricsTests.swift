import XCTest
@testable import OnlyCue

/// Regression invariant for issue #297. The cue-list inspector column had
/// two independent width contracts after `b8dfae0` removed the isolating
/// inner `VSplitView`: `CueListPane`'s own `.frame(minWidth: 240)` and
/// `DocumentView`'s `.inspectorColumnWidth(min: 240, ideal: 300, max: 400)`.
/// When they can disagree mid-drag the `NSSplitView` constraint loop
/// asserts. The fix makes `CueListInspectorMetrics` the single source of
/// truth used by the `.inspector` modifier, and `CueListPane` no longer
/// declares its own conflicting fixed min width.
///
/// This test is the deterministic, CI-stable guard (the UI stress test in
/// `SplitDividerCrashUITests` is the behavioural guard but is hit-test
/// fragile headless). If a future change reintroduces a divergent literal,
/// these assertions fail fast.
final class CueListInspectorMetricsTests: XCTestCase {

    func test_metrics_areOrdered() {
        XCTAssertLessThan(CueListInspectorMetrics.minWidth, CueListInspectorMetrics.idealWidth)
        XCTAssertLessThan(CueListInspectorMetrics.idealWidth, CueListInspectorMetrics.maxWidth)
    }

    func test_minWidth_matchesDocumentedContract() {
        // The documented inspector minimum (data-model/UI spec) is 240.
        XCTAssertEqual(CueListInspectorMetrics.minWidth, 240)
        XCTAssertEqual(CueListInspectorMetrics.idealWidth, 300)
        XCTAssertEqual(CueListInspectorMetrics.maxWidth, 400)
    }

    func test_cueListPaneMinWidth_isTheSharedMetric_notAnIndependentLiteral() {
        // CueListPane must defer to the shared metric so it cannot declare a
        // value that diverges from the .inspectorColumnWidth contract.
        XCTAssertEqual(CueListPane.minPaneWidth, CueListInspectorMetrics.minWidth)
    }
}
