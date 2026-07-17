import CoreGraphics

/// Vertical split for the preview pane. Figma `318:1639`: a video clip takes the
/// top ~74% of the preview well and the waveform/timeline a ~26% band beneath it
/// (≈150pt of ≈602pt at the design height) — not the old fixed 100pt. Pure so
/// the proportions are unit-tested without a view.
enum PreviewLayout {

    /// Leading inset of the Cue/Lyric/Show switcher (Figma 318:1250 —
    /// EditorModeSwitcher at x=16). The switcher bar is left-aligned, not
    /// centered.
    static let switcherLeadingInset: CGFloat = 16

    /// The preview pane's outer horizontal gutter (Figma 318:1252) — the
    /// waveform well and the LTC strip both sit inside it. Equal to the standard
    /// `DS.Space.lg`.
    static let trackHorizontalInset: CGFloat = 16

    /// The waveform's *inner* horizontal content inset (`WaveformContainer`) —
    /// the playhead/markers/seek surface live inside this on top of the outer
    /// gutter. Equal to `DS.Space.sm`.
    static let trackContentInset: CGFloat = 8

    /// The total horizontal inset of the playhead track from the detail-column
    /// edge (#663): outer gutter + waveform content inset. The waveform reaches
    /// it as `trackHorizontalInset` (PreviewPane) + `trackContentInset`
    /// (WaveformContainer); the LTC strip applies it directly. Both then map
    /// time→x via `CueMarkersGeometry.position` across the identical x-range, so
    /// their playheads stay on one vertical line at every window width.
    static let playheadTrackInset: CGFloat = trackHorizontalInset + trackContentInset

    /// Height of the timeline/waveform band beneath the video, for a preview of
    /// `totalHeight`. ~26% normally (~40% for the taller breakdown lanes), with
    /// a readable floor, and never more than half (the video stays dominant).
    static func videoTimelineHeight(totalHeight: CGFloat, breakdown: Bool) -> CGFloat {
        let proportion: CGFloat = breakdown ? 0.40 : 0.26
        let floor: CGFloat = breakdown ? 200 : 120
        return min(totalHeight * 0.5, max(floor, totalHeight * proportion))
    }
}
