import CoreGraphics
import SwiftUI

/// Shared widths for the cue list's Time, Number, and Fade columns.
///
/// Persisted globally via `@AppStorage` (keys below) and read by both the
/// header row and `CueRowView` so they stay aligned during drag-resize.
/// Name column intentionally has no entry — it absorbs the remaining width.
enum CueListColumnWidths {

    static let timeRange: ClosedRange<CGFloat> = 64...180
    static let numberRange: ClosedRange<CGFloat> = 40...120
    static let fadeRange: ClosedRange<CGFloat> = 56...160

    static let timeDefault: CGFloat = 96
    static let numberDefault: CGFloat = 56
    static let fadeDefault: CGFloat = 72

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
