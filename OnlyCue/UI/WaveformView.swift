import SwiftUI

/// Renders the audio waveform as a **dual envelope** (#734): a filled RMS
/// "body" for a loudness-faithful overview (#632) with a fainter peak "outline"
/// layered behind it so transients stay visible at deep zoom (the user places
/// cues by eyeballing the sharpest transient). Both layers are collapsed to the
/// pixel width on screen (`WaveformPeakBucketer`) and normalized at render time
/// so detail scales with horizontal zoom and progressive streaming stays
/// self-consistent.
struct WaveformView: View {

    /// Un-normalized per-slice buckets (peak + RMS). Normalization happens at
    /// render time (`normalizedEnvelope`) rather than at generation, so a
    /// partially-streamed clip paints a self-consistent envelope (#734, spec §5).
    let buckets: [WaveformBucket]
    /// The waveform is achromatic chrome (ADR-024; Figma 318:1228) — a neutral
    /// grey, not the cue/indigo accent (chroma is reserved for cue-type color).
    var color: Color = DS.Color.textSecondary

    static let minHairline: CGFloat = 0.5

    /// Opacity of the peak-outline layer. Same achromatic hue as the body, just
    /// fainter, so transients read as a light "halo" beyond the solid loudness
    /// body. Drawn UNDER the opaque body so that where `peak == rms` the body
    /// fully occludes it — collapsing to the pre-#734 single filled envelope.
    static let peakOutlineOpacity: Double = 0.5

    /// Fraction of the half-height the loudest (normalized 1.0) peak is allowed
    /// to fill. Below 1 so the envelope leaves a margin and never touches the
    /// well's top/bottom edge — normalized peaks otherwise slam a loud master
    /// flush against the boundary (issue #628).
    static let verticalFillRatio: CGFloat = 0.85

    /// Mirrored half-height (above and below the midline) for a normalized
    /// `peak` in a well of half-height `midY`. Clamped to a minimum hairline so
    /// silence still shows a centerline, and to the usable band so the loudest
    /// peak stops short of the edge.
    static func halfHeight(peak: Float, midY: CGFloat) -> CGFloat {
        let usable = midY * verticalFillRatio
        return min(max(CGFloat(peak) * usable, minHairline), usable)
    }

    /// X position for peak column `index` of `count`, using the same continuous
    /// `fraction * width` mapping the playhead and cue markers use
    /// (`CueMarkersGeometry.position`). The column sits at the center of its time
    /// bucket — `(index + 0.5) / count` — so a transient lines up with its
    /// playhead at every zoom level (#540). The previous `index / (count - 1)`
    /// fence-post spacing drifted from that mapping, worst at the right edge.
    static func columnX(index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return (CGFloat(index) + 0.5) / CGFloat(count) * width
    }

    /// Number of envelope columns to draw for a given content width. Capped at
    /// the source resolution (`peakCount`) so deep horizontal zoom doesn't
    /// upsample the buckets into tens of thousands of columns and re-draw a huge
    /// path every follow frame (#681). Lossless: above the source resolution the
    /// extra columns would only be collinear interpolations of the same buckets.
    static func bucketCount(width: CGFloat, peakCount: Int) -> Int {
        min(Int(width.rounded()), max(peakCount, 0))
    }

    /// Collapses the loaded buckets to `count` columns and normalizes BOTH the
    /// RMS body and the peak outline by the SAME divisor — the global peak-max of
    /// the loaded buckets (spec §5). One shared divisor (not independent
    /// per-statistic maxes) is what guarantees `rms[i] <= peak[i]` at every
    /// column, so the filled body never spills past the peak outline. Both
    /// arrays are in `0...1`, equal length; all-silence collapses to flat zeros
    /// (no divide-by-zero).
    static func normalizedEnvelope(buckets: [WaveformBucket], count: Int) -> (rms: [Float], peak: [Float]) {
        let peakColumns = WaveformPeakBucketer.bucket(peaks: buckets.map(\.peak), into: count)
        let rmsColumns = WaveformPeakBucketer.bucketRMS(buckets.map(\.rms), into: count)
        guard let maxPeak = buckets.map(\.peak).max(), maxPeak > WaveformBucket.silenceFloor else {
            return (rmsColumns.map { _ in 0 }, peakColumns.map { _ in 0 })
        }
        return (rmsColumns.map { $0 / maxPeak }, peakColumns.map { $0 / maxPeak })
    }

    var body: some View {
        Canvas { context, size in
            guard !buckets.isEmpty, size.width > 0, size.height > 0 else { return }

            let count = Self.bucketCount(width: size.width, peakCount: buckets.count)
            let envelope = Self.normalizedEnvelope(buckets: buckets, count: count)
            guard envelope.rms.count > 1 else { return }

            let midY = size.height / 2

            // Peak outline UNDER the RMS body: because the body color is opaque
            // it fully occludes the outline in their overlap, leaving only the
            // transient halo beyond the loudness body — and when peak == rms the
            // body covers the outline exactly (pre-#734 single-envelope look).
            context.fill(
                envelopePath(values: envelope.peak, midY: midY, width: size.width),
                with: .color(color.opacity(Self.peakOutlineOpacity))
            )
            context.fill(
                envelopePath(values: envelope.rms, midY: midY, width: size.width),
                with: .color(color)
            )
        }
        .accessibilityIdentifier("waveform")
    }

    /// Builds the closed, mirrored envelope path for one collapsed column array —
    /// top contour left→right, bottom contour right→left — using the shared
    /// `columnX`/`halfHeight` geometry so both layers register pixel-for-pixel.
    private func envelopePath(values: [Float], midY: CGFloat, width: CGFloat) -> Path {
        let count = values.count
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = Self.columnX(index: index, count: count, width: width)
            let y = midY - Self.halfHeight(peak: value, midY: midY)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        for index in stride(from: count - 1, through: 0, by: -1) {
            let x = Self.columnX(index: index, count: count, width: width)
            path.addLine(to: CGPoint(x: x, y: midY + Self.halfHeight(peak: values[index], midY: midY)))
        }
        path.closeSubpath()
        return path
    }
}
