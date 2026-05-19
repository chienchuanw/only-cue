import SwiftUI

/// Single source of truth for the cue-list `.inspector` column's width
/// contract. Issue #297: `CueListPane` previously also declared its own
/// `.frame(minWidth: 240)`, a second contract that could disagree with
/// `.inspectorColumnWidth` mid-drag and feed the `NSSplitView` constraint
/// loop. Both the `.inspector` modifier and `CueListPane.minPaneWidth`
/// resolve to these values so they can never diverge.
enum CueListInspectorMetrics {
    static let minWidth: CGFloat = 240
    static let idealWidth: CGFloat = 300
    static let maxWidth: CGFloat = 400
}

extension View {
    /// Applies the cue-list `.inspector` column width contract from the
    /// single source of truth. Using this instead of a literal
    /// `.inspectorColumnWidth(min:ideal:max:)` at the call site makes a
    /// divergent contract (the issue #297 constraint-loop precursor)
    /// impossible to introduce.
    func cueListInspectorColumnWidth() -> some View {
        inspectorColumnWidth(
            min: CueListInspectorMetrics.minWidth,
            ideal: CueListInspectorMetrics.idealWidth,
            max: CueListInspectorMetrics.maxWidth
        )
    }
}
