import SwiftUI

/// One editor mode's pane arrangement. A pure value: no window, no AppKit, no
/// persistence — so the clamping rule (spec decision 8) is unit-testable.
///
/// Collapsed panes keep their width. Collapsing is a visibility flag, never a
/// width of zero, so `⌥⌘I` twice returns the inspector to the width it had and
/// clamping on a narrow window does not destroy the value the user chose on a
/// wide one.
struct PaneLayout: Codable, Equatable {

    var sidebarWidth: CGFloat
    var isSidebarCollapsed: Bool
    var inspectorWidth: CGFloat
    var isInspectorCollapsed: Bool

    static let `default` = Self(
        sidebarWidth: SidebarMetrics.idealWidth,
        isSidebarCollapsed: false,
        inspectorWidth: CueListInspectorMetrics.idealWidth,
        isInspectorCollapsed: false
    )
}

extension PaneLayout {

    /// The centre pane's floor, mirroring `DocumentView.mainPane`'s
    /// `.frame(minWidth: 560)`. Below this the waveform well and transport bar
    /// start clipping.
    static let centerMinimumWidth: CGFloat = 560

    /// The width each pane actually occupies right now.
    var effectiveSidebarWidth: CGFloat { isSidebarCollapsed ? 0 : sidebarWidth }
    var effectiveInspectorWidth: CGFloat { isInspectorCollapsed ? 0 : inspectorWidth }

    /// Fits this layout into `available` points of window width, shedding in a
    /// fixed order: shrink the inspector to its minimum, collapse the
    /// inspector, shrink the sidebar to its minimum, collapse the sidebar.
    ///
    /// Never widens a pane, and never mutates the stored preset — callers clamp
    /// a *copy* on apply (spec decision 8: "clamped on apply, never rewritten";
    /// rewriting would silently shrink the user's workspace forever the moment
    /// they undocked from an external display).
    func clamped(toAvailableWidth available: CGFloat) -> PaneLayout {
        var result = self

        func deficit() -> CGFloat {
            let used = result.effectiveSidebarWidth + result.effectiveInspectorWidth
            return Self.centerMinimumWidth - (available - used)
        }

        guard deficit() > 0 else { return result }

        if !result.isInspectorCollapsed {
            result.inspectorWidth = max(
                CueListInspectorMetrics.minWidth,
                result.inspectorWidth - deficit()
            )
            guard deficit() > 0 else { return result }
            result.isInspectorCollapsed = true
            guard deficit() > 0 else { return result }
        }

        if !result.isSidebarCollapsed {
            result.sidebarWidth = max(SidebarMetrics.minWidth, result.sidebarWidth - deficit())
            guard deficit() > 0 else { return result }
            result.isSidebarCollapsed = true
        }

        return result
    }
}
