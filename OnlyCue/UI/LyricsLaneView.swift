import SwiftUI

/// The lyric lane — a band at the bottom of the waveform's scrollable content
/// showing each line positioned by its effective time. Because it lives inside
/// `WaveformContainer`'s zoomable `ZStack`, it inherits horizontal zoom/scroll.
/// Click-to-seek; collapses to ticks when lines pack too tightly.
struct LyricsLaneView: View {

    let lyrics: Lyrics
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    private static let laneHeight: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let collapse = LyricsLaneLayout.shouldCollapseToTicks(
                lineCount: lyrics.lines.count,
                contentWidth: width
            )
            ZStack(alignment: .bottomLeading) {
                ForEach(lyrics.lines) { line in
                    marker(for: line, width: width, collapsed: collapse)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: Self.laneHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyricsLane")
    }

    @ViewBuilder
    private func marker(for line: LyricLine, width: CGFloat, collapsed: Bool) -> some View {
        let position = CueMarkersGeometry.position(
            forTime: lyrics.effectiveTime(of: line),
            width: width,
            duration: duration
        )
        Group {
            if collapsed {
                Rectangle()
                    .fill(.purple.opacity(0.7))
                    .frame(width: 1.5, height: 12)
            } else {
                Text(line.text.isEmpty ? "\u{266A}" : line.text)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.purple.opacity(0.18)))
            }
        }
        .offset(x: position)
        .onTapGesture { onSeek(lyrics.effectiveTime(of: line)) }
        .accessibilityIdentifier("lyricsLaneMarker-\(line.id.uuidString)")
    }
}
