import CoreGraphics
import Foundation

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

    /// Max width for the compact chip at `forTime`: the horizontal gap to the
    /// next placed line on its right (or the lane's right edge for the last
    /// chip), minus `gap`, clamped to `[0, cap]`. Capping each chip to its slot
    /// keeps a long line's text from overrunning its neighbor (Figma 318:1263 —
    /// fixed-width chips with ellipsis). Pure so overlap behavior is unit-tested.
    static func chipMaxWidth(
        forTime time: TimeInterval,
        allTimes: [TimeInterval],
        duration: TimeInterval,
        contentWidth: CGFloat,
        gap: CGFloat = 6,
        cap: CGFloat = 140
    ) -> CGFloat {
        guard contentWidth > 0, duration > 0 else { return cap }
        func position(_ seconds: TimeInterval) -> CGFloat {
            min(max(0, contentWidth * CGFloat(seconds / duration)), contentWidth)
        }
        let here = position(time)
        let nextEdge = allTimes.filter { $0 > time }.min().map(position) ?? contentWidth
        let available = nextEdge - here - gap
        return max(0, min(cap, available))
    }
}
