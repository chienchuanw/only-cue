import CoreGraphics
import Foundation

/// Pure x↔time math for the lyric lane — click-to-drop placement and
/// drag-to-retime. Kept separate from `CueMarkersGeometry` so the lane has one
/// clearly-named helper; the formulae match (the lane shares the waveform's
/// time→x mapping).
enum LyricsLaneInteraction {

    /// The media time at horizontal coordinate `x` in the lane's content space,
    /// clamped to `0...duration`.
    static func mediaTime(forX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration > 0 else { return 0 }
        return min(max(Double(x / width) * duration, 0), duration)
    }

    /// The media time of a chip dragged by `dx` points from `fromMediaTime`,
    /// clamped to `0...duration`.
    static func draggedMediaTime(
        fromMediaTime: TimeInterval,
        dx: CGFloat,
        width: CGFloat,
        duration: TimeInterval
    ) -> TimeInterval {
        guard width > 0, duration > 0 else { return fromMediaTime }
        return min(max(fromMediaTime + Double(dx / width) * duration, 0), duration)
    }
}
