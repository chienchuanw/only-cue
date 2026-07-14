import SwiftUI

/// Renders the audio waveform as a filled, mirrored amplitude envelope (the
/// continuous "blob" look used by DAWs) rather than discrete bars. The source
/// `peaks` array is high-resolution; `WaveformPeakBucketer` collapses it to the
/// pixel width actually on screen so detail scales with horizontal zoom.
struct WaveformView: View {

    let peaks: [Float]
    /// The waveform is achromatic chrome (ADR-024; Figma 318:1228) — a neutral
    /// grey, not the cue/indigo accent (chroma is reserved for cue-type color).
    var color: Color = DS.Color.textSecondary

    private static let minHairline: CGFloat = 0.5

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

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }

            let columns = WaveformPeakBucketer.bucket(
                peaks: peaks,
                into: Int(size.width.rounded())
            )
            guard columns.count > 1 else { return }

            let midY = size.height / 2
            let count = columns.count

            func halfHeight(_ peak: Float) -> CGFloat {
                min(max(CGFloat(peak) * midY, Self.minHairline), midY)
            }

            var path = Path()
            // Top contour, left -> right.
            for (index, peak) in columns.enumerated() {
                let x = Self.columnX(index: index, count: count, width: size.width)
                let y = midY - halfHeight(peak)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            // Bottom contour, right -> left.
            for index in stride(from: count - 1, through: 0, by: -1) {
                let x = Self.columnX(index: index, count: count, width: size.width)
                path.addLine(to: CGPoint(x: x, y: midY + halfHeight(columns[index])))
            }
            path.closeSubpath()

            context.fill(path, with: .color(color))
        }
        .accessibilityIdentifier("waveform")
    }
}
