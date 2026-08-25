import SwiftUI

/// The read-only cue overlay on the Mini Player progress bar (#773): one 2×9pt
/// vertical tick per cue, in the cue type's colour. The track is 4pt tall, so
/// ~2.5pt of each tick overhangs onto the panel background — that overhang, not
/// an outline, is what keeps a tick legible over the indigo fill. Widening the
/// ticks with a stroke would fuse cues two seconds apart into one blob at the
/// panel's ~2pt-per-second density.
///
/// `Equatable` + `Canvas` on purpose: `MiniPlayerHostView` re-derives its model
/// every frame while playing, so this row repaints at 30–60Hz. Both stored
/// properties are playback-independent, which lets SwiftUI skip the layer
/// entirely between seeks and resizes instead of relayouting a `ForEach` of
/// shapes hundreds of times a second in an always-on-top panel.
///
/// Spec: `docs/superpowers/specs/2026-08-26-miniplayer-cue-markers-design.md`.
struct MiniPlayerCueMarkers: View, Equatable {

    let markers: [MiniPlayerModel.CueMarker]
    /// The progress bar's measured width; ticks are positioned against it.
    let width: CGFloat

    private static let lineWidth: CGFloat = 2
    static let height: CGFloat = 9

    var body: some View {
        Canvas { context, _ in
            for marker in markers {
                let rect = CGRect(
                    x: marker.fraction * width - Self.lineWidth / 2,
                    y: 0,
                    width: Self.lineWidth,
                    height: Self.height
                )
                context.fill(Path(rect), with: .color(Color(hex: marker.colorHex) ?? .accentColor))
            }
        }
        .frame(width: width, height: Self.height)
        // Purely an overview — clicks belong to the bar's seek gesture.
        .allowsHitTesting(false)
    }
}
