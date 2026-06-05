import CoreGraphics

/// Vertical split for the preview pane. Figma `318:1639`: a video clip takes the
/// top ~74% of the preview well and the waveform/timeline a ~26% band beneath it
/// (≈150pt of ≈602pt at the design height) — not the old fixed 100pt. Pure so
/// the proportions are unit-tested without a view.
enum PreviewLayout {

    /// Height of the timeline/waveform band beneath the video, for a preview of
    /// `totalHeight`. ~26% normally (~40% for the taller breakdown lanes), with
    /// a readable floor, and never more than half (the video stays dominant).
    static func videoTimelineHeight(totalHeight: CGFloat, breakdown: Bool) -> CGFloat {
        let proportion: CGFloat = breakdown ? 0.40 : 0.26
        let floor: CGFloat = breakdown ? 200 : 120
        return min(totalHeight * 0.5, max(floor, totalHeight * proportion))
    }
}
