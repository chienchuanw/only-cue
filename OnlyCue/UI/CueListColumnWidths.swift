import CoreGraphics

/// Shared widths for the cue list's Time and Number columns.
///
/// Persisted globally via `@AppStorage` (keys below) and read by both the
/// header row and `CueRowView` so they stay aligned during drag-resize.
/// Name column intentionally has no entry — it absorbs the remaining width.
enum CueListColumnWidths {

    static let timeRange: ClosedRange<CGFloat> = 64...180
    static let numberRange: ClosedRange<CGFloat> = 40...120

    static let timeDefault: CGFloat = 96
    static let numberDefault: CGFloat = 56

    static let timeStorageKey = "cueList.timeColumnWidth"
    static let numberStorageKey = "cueList.numberColumnWidth"

    static func clampTime(_ width: CGFloat) -> CGFloat {
        min(max(width, timeRange.lowerBound), timeRange.upperBound)
    }

    static func clampNumber(_ width: CGFloat) -> CGFloat {
        min(max(width, numberRange.lowerBound), numberRange.upperBound)
    }
}
