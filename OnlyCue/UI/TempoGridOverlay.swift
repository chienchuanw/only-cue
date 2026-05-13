import SwiftUI

/// The beat/bar grid overlay drawn on the waveform pane when `View → Show Tempo
/// Grid` is on (epic #199): thin lines on beats, heavier lines on downbeats, plus
/// a distinct marker at each tempo-section boundary. Decorative + non-interactive
/// — the tempo map is edited via `Tools → Tempo Map…` and acts as a snap target
/// for cues; this view never handles hits. Drawn into a `Canvas` so a long,
/// zoomed-in track stays cheap.
struct TempoGridOverlay: View {

    let tempoMap: TempoMap
    let duration: TimeInterval

    /// Cap on beat lines drawn — past it the grid is visual mush anyway (and slow);
    /// zoom in to see a denser stretch.
    private static let maxLines = 20_000

    var body: some View {
        Canvas { context, size in
            guard duration > 0, size.width > 0, !tempoMap.sections.isEmpty else { return }
            for entry in tempoMap.beatTimes(in: 0...duration, itemDuration: duration).prefix(Self.maxLines) {
                let position = CueMarkersGeometry.position(forTime: entry.time, width: size.width, duration: duration)
                let lineWidth: CGFloat = entry.isDownbeat ? 1.5 : 0.75
                let rect = CGRect(x: position - lineWidth / 2, y: 0, width: lineWidth, height: size.height)
                context.fill(Path(rect), with: .color(.secondary.opacity(entry.isDownbeat ? 0.45 : 0.2)))
            }
            for section in tempoMap.sections where section.startSeconds > 0 {
                let position = CueMarkersGeometry.position(forTime: section.startSeconds, width: size.width, duration: duration)
                context.fill(Path(CGRect(x: position - 1, y: 0, width: 2, height: size.height)), with: .color(.orange.opacity(0.5)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("tempoGridOverlay")
    }
}
