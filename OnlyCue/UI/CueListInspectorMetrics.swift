import SwiftUI

/// Single source of truth for the cue-list inspector pane's width contract.
/// Issue #297: `CueListPane` previously also declared its own
/// `.frame(minWidth: 240)`, a second contract that could disagree with the
/// inspector's own width mid-drag and feed the `NSSplitView` constraint loop.
/// Both the pane-width modifier and `CueListPane.minPaneWidth` resolve to
/// these values so they can never diverge. (The inspector is now an `HStack`
/// child rather than an `.inspector` column — see #617 — but the divergent-
/// contract guard is unchanged.)
enum CueListInspectorMetrics {
    // 340 (was 240): the detail/center column is `maxWidth: .infinity` (greedy,
    // #516), so at the default window it pins the inspector at this minimum.
    // 340 keeps the inspector wide enough that the playhead clock and the
    // TIME/#/NAME/FADE columns fit without clipping past the window edge (Figma
    // 318:1311/318:1312, ~360). Still > the header floor (234), so the #297
    // constraint-loop guard (`headerMinimumWidth ≤ minWidth`) holds.
    static let minWidth: CGFloat = 340
    // 360 matches Figma 318:1311 (sidebar 240 + center 680 + inspector 360 =
    // 1280), so the cue NAME column gets its full width instead of truncating.
    static let idealWidth: CGFloat = 360
    static let maxWidth: CGFloat = 400
}

extension View {
    /// Applies the cue-list inspector pane's width contract from the single
    /// source of truth. Using this instead of literal widths at the call site
    /// makes a divergent contract (the issue #297 constraint-loop precursor)
    /// impossible to introduce. Frame-based (not `.inspectorColumnWidth`)
    /// because the inspector now lives in a plain `HStack` — any
    /// NSSplitView-backed split in the detail column (`.inspector` /
    /// `HSplitView`) inflated the window's minimum width past the 1280pt
    /// design width (#617).
    func cueListInspectorPaneWidth() -> some View {
        frame(
            minWidth: CueListInspectorMetrics.minWidth,
            idealWidth: CueListInspectorMetrics.idealWidth,
            maxWidth: CueListInspectorMetrics.maxWidth
        )
    }
}
