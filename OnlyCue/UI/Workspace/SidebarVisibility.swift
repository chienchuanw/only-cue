import SwiftUI

/// Maps between `PaneLayout.isSidebarCollapsed` and SwiftUI's
/// `NavigationSplitViewVisibility` so the same collapse state persists in a
/// preset and drives the native sidebar. `.detailOnly` is the only value that
/// hides the sidebar in a two-column split; everything else shows it.
enum SidebarVisibility {
    static func isCollapsed(_ visibility: NavigationSplitViewVisibility) -> Bool {
        visibility == .detailOnly
    }
    static func visibility(isCollapsed: Bool) -> NavigationSplitViewVisibility {
        isCollapsed ? .detailOnly : .all
    }
}
