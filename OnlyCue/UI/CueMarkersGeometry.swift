import CoreGraphics
import Foundation

enum CueMarkersGeometry {

    static func position(forTime time: TimeInterval, width: CGFloat, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    static func time(originalTime: TimeInterval, dx: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return originalTime }
        let proposed = originalTime + Double(dx / width) * duration
        return min(max(proposed, 0), duration)
    }

    /// Inverse of `position(forTime:width:duration:)` — maps a horizontal
    /// coordinate in the waveform's content space to a clamped media time.
    static func time(forX xCoordinate: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration > 0 else { return 0 }
        let proposed = Double(xCoordinate / width) * duration
        return min(max(proposed, 0), duration)
    }

    /// Returns the pixel Δ that, when applied to `anchorTime`, lands on the nearest
    /// beat of `grid`. Falls back to `dxPixels` unchanged when the grid is empty,
    /// width is non-positive, or no covering segment exists. Used by group drag so
    /// the whole selection rides along by the snapped pixel Δ (anchored on the
    /// grabbed cue), which preserves inter-cue spacing.
    static func snapDeltaToBeat(
        dxPixels: CGFloat,
        anchorTime: TimeInterval,
        grid: DerivedTempoGrid,
        width: CGFloat,
        duration: TimeInterval
    ) -> CGFloat {
        guard !grid.isEmpty, width > 0, duration > 0 else { return dxPixels }
        let proposedTime = time(originalTime: anchorTime, dx: dxPixels, width: width, duration: duration)
        guard let snapped = grid.nearestBeat(toSeconds: proposedTime, itemDuration: duration) else {
            return dxPixels
        }
        return CGFloat((snapped - anchorTime) / duration) * width
    }
}
