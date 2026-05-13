import SwiftUI

/// Renders the audio waveform as a filled, mirrored amplitude envelope (the
/// continuous "blob" look used by DAWs) rather than discrete bars. The source
/// `peaks` array is high-resolution; `WaveformPeakBucketer` collapses it to the
/// pixel width actually on screen so detail scales with horizontal zoom.
struct WaveformView: View {

    let peaks: [Float]
    var color: Color = .accentColor
    var verticalZoom: CGFloat = 1

    private static let minHairline: CGFloat = 0.5

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }

            let columns = WaveformPeakBucketer.bucket(
                peaks: peaks,
                into: Int(size.width.rounded())
            )
            guard columns.count > 1 else { return }

            let midY = size.height / 2
            let dx = size.width / CGFloat(columns.count - 1)

            func halfHeight(_ peak: Float) -> CGFloat {
                min(max(CGFloat(peak) * midY * verticalZoom, Self.minHairline), midY)
            }

            var path = Path()
            // Top contour, left -> right.
            for (index, peak) in columns.enumerated() {
                let x = CGFloat(index) * dx
                let y = midY - halfHeight(peak)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            // Bottom contour, right -> left.
            for index in stride(from: columns.count - 1, through: 0, by: -1) {
                let x = CGFloat(index) * dx
                path.addLine(to: CGPoint(x: x, y: midY + halfHeight(columns[index])))
            }
            path.closeSubpath()

            context.fill(path, with: .color(color))
        }
        .accessibilityIdentifier("waveform")
    }
}
