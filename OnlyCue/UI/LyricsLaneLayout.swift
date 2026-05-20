import CoreGraphics

/// Pure layout decisions for the lyric lane. The lane shows readable text when
/// each line gets enough horizontal room; once lines pack tighter than
/// `minWidthPerLine`, it collapses to ticks (the tempo-grid strategy).
enum LyricsLaneLayout {

    /// Minimum points per line for text rendering. Below this, collapse.
    static let minWidthPerLine: CGFloat = 40

    static func shouldCollapseToTicks(lineCount: Int, contentWidth: CGFloat) -> Bool {
        guard lineCount > 0 else { return false }
        guard contentWidth > 0 else { return true }
        return contentWidth / CGFloat(lineCount) < minWidthPerLine
    }
}
