import CoreGraphics
import SwiftUI

/// Shared widths for the cue list's Time, Number, and Fade columns.
///
/// Persisted globally via `@AppStorage` (keys below) and read by both the
/// header row and `CueRowView` so they stay aligned during drag-resize.
/// Name column intentionally has no entry — it absorbs the remaining width.
enum CueListColumnWidths {

    // The time column shows an 11-char SMPTE string (`HH:MM:SS:FF`, ~86pt at
    // 13pt monospaced). Its floor must keep the full string on one line even
    // when the pane is squeezed to its 240pt minimum (Figma 318:1228); the
    // floor stays within the #297 budget (compressible floor <= 200, asserted
    // by CueListPaneMinWidthTests).
    static let timeRange: ClosedRange<CGFloat> = 92...180
    static let numberRange: ClosedRange<CGFloat> = 40...120
    static let fadeRange: ClosedRange<CGFloat> = 56...160

    // Defaults sit just above the compressible floors so the flexible Name
    // column gets the most room (closer to Figma 318:1326, where Time/#/Fade
    // are tight and the name fills), while staying strictly wider than the
    // floors so columns retain compression headroom under width pressure
    // (#297). Floors/ranges and the header-floor budget are unchanged.
    static let timeDefault: CGFloat = 96
    static let numberDefault: CGFloat = 44
    static let fadeDefault: CGFloat = 60

    static let timeStorageKey = "cueList.timeColumnWidth"
    static let numberStorageKey = "cueList.numberColumnWidth"
    static let fadeStorageKey = "cueList.fadeColumnWidth"

    static func clampTime(_ width: CGFloat) -> CGFloat {
        min(max(width, timeRange.lowerBound), timeRange.upperBound)
    }

    static func clampNumber(_ width: CGFloat) -> CGFloat {
        min(max(width, numberRange.lowerBound), numberRange.upperBound)
    }

    static func clampFade(_ width: CGFloat) -> CGFloat {
        min(max(width, fadeRange.lowerBound), fadeRange.upperBound)
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
