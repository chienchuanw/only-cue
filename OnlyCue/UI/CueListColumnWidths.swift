import CoreGraphics
import SwiftUI

/// Shared widths for the cue list's Number and Info columns.
///
/// Persisted globally via `@AppStorage` (keys below) and read by both the
/// header row and `CueRowView` so they stay aligned during drag-resize.
/// The Name column intentionally has no entry — it absorbs the remaining width
/// and stays the widest column (#661).
enum CueListColumnWidths {

    // The number column shows the (short) cue number. Its floor keeps a
    // one/two-digit number legible even when the pane is squeezed to its 240pt
    // minimum; the floor stays within the #297 budget (compressible floor <=
    // inspector min, asserted by CueListPaneMinWidthTests).
    static let numberRange: ClosedRange<CGFloat> = 40...120

    // The Info column previews the cue's notes. Kept narrower than Name so the
    // name stays the primary, widest column (#661); resizable within range.
    static let infoRange: ClosedRange<CGFloat> = 72...220

    // Defaults sit just above the compressible floors so the flexible Name
    // column gets the most room, while staying strictly wider than the floors
    // so columns retain compression headroom under width pressure (#297).
    static let numberDefault: CGFloat = 44
    static let infoDefault: CGFloat = 110

    static let numberStorageKey = "cueList.numberColumnWidth"
    static let infoStorageKey = "cueList.infoColumnWidth"

    static func clampNumber(_ width: CGFloat) -> CGFloat {
        min(max(width, numberRange.lowerBound), numberRange.upperBound)
    }

    static func clampInfo(_ width: CGFloat) -> CGFloat {
        min(max(width, infoRange.lowerBound), infoRange.upperBound)
    }
}

extension View {
    /// Lays out a fixed cue-list column. Issue #297: the column resolves to
    /// `width` whenever space allows (visually identical to the old rigid
    /// `.frame(width:)`), but is allowed to compress down to `range`'s lower
    /// bound under width pressure. A rigid `.frame(width:)` pinned the pane's
    /// minimum width above the inspector column minimum, so the outer
    /// `NSSplitView` could never reach 240 without the content demanding more
    /// — the constraint-update recursion. Header and `CueRowView` MUST use
    /// this identical modifier so the columns stay aligned at every width.
    func cueColumnFrame(
        width: CGFloat,
        range: ClosedRange<CGFloat>,
        alignment: Alignment = .leading
    ) -> some View {
        frame(
            minWidth: range.lowerBound,
            idealWidth: width,
            maxWidth: width,
            alignment: alignment
        )
    }
}
