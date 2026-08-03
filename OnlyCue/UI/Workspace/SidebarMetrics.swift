import SwiftUI

/// Single source of truth for the item-list sidebar's width contract, extracted
/// from the literals that used to sit inline at `DocumentView.swift:61`. The
/// mirror of `CueListInspectorMetrics` on the other side of the window: with
/// workspace presets storing sidebar widths (#714), two places declaring the
/// bounds could disagree and let a stored preset clamp against a range the
/// window does not actually honour.
enum SidebarMetrics {
    /// 240 — the Figma 318:1311 sidebar width and the native ideal.
    static let minWidth: CGFloat = 240
    static let idealWidth: CGFloat = 240
    /// 320 — beyond this the 1280pt design width cannot seat a 560pt centre
    /// pane plus a 340pt inspector.
    static let maxWidth: CGFloat = 320
}
