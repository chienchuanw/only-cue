import CoreGraphics

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
