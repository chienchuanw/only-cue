import SwiftUI

struct WaveformView: View {

    let peaks: [Float]
    var color: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let midY = size.height / 2
            let columnWidth = size.width / CGFloat(peaks.count)
            let barWidth = max(columnWidth - 1, 0.5)
            let shading = context.resolve(.color(color))
            for (index, peak) in peaks.enumerated() {
                let halfHeight = max(CGFloat(peak) * midY, 0.5)
                let xCenter = (CGFloat(index) + 0.5) * columnWidth
                let rect = CGRect(
                    x: xCenter - barWidth / 2,
                    y: midY - halfHeight,
                    width: barWidth,
                    height: halfHeight * 2
                )
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: shading)
            }
        }
        .accessibilityIdentifier("waveform")
    }
}
