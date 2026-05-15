import AppKit
import SwiftUI

/// Full-bleed transparent surface that bears the click-to-seek and
/// hold-to-scrub gesture for the main-pane waveform.
///
/// Renders nothing visible. Lives BELOW `CueMarkersOverlay` in
/// `WaveformContainer`'s `ZStack` so a press on a cue marker reaches the
/// marker view instead of being absorbed here. The visual playhead line +
/// time-label badge are rendered separately by `WaveformPlayheadVisual`,
/// which sits ABOVE the markers with hit-testing disabled.
///
/// Click handling uses a `SpatialTapGesture` (bare clicks); hold-to-scrub
/// uses a `DragGesture(minimumDistance: 1)`. The two compose with
/// `.simultaneously` and don't conflict in practice — see the in-line
/// comment in `body`. Pause-on-press / resume-on-release physics for
/// scrub live in `TimelineScrubOrchestrator`.
struct WaveformSeekSurface: View {

    let engine: PlayerEngine
    let duration: TimeInterval
    @Binding var scrub: ScrubController
    @Binding var seekTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Color.clear
                .contentShape(Rectangle())
                // SpatialTapGesture handles bare clicks (no translation).
                // DragGesture(minimumDistance: 1) handles hold-to-scrub.
                // The two run simultaneously and don't conflict: a click
                // never accumulates 1 pt of translation so the drag stays
                // idle, and a drag is never a bare touch-up at the press
                // point so the tap stays idle.
                //
                // Why `minimumDistance: 1` on the drag (not 0): with both
                // this surface and a `CueMarkerView` carrying drag
                // gestures, the previous `minimumDistance: 0` here meant
                // SwiftUI delivered every press to whichever sibling was
                // topmost — absorbing marker clicks (#285). Bumping to 1
                // lets the marker's `minimumDistance: 0` win arbitration
                // on a press that lands on a cap.
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in seek(toX: value.location.x, width: width) }
                        .simultaneously(with: timelineDragGesture(width: width))
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active: NSCursor.openHand.set()
                    case .ended: NSCursor.arrow.set()
                    }
                }
                .accessibilityIdentifier("waveformSeekSurface")
        }
    }

    private func seek(toX x: CGFloat, width: CGFloat) {
        let target = CueMarkersGeometry.time(forX: x, width: width, duration: duration)
        seekTask?.cancel()
        seekTask = Task {
            await engine.seek(to: target)
        }
    }

    private func timelineDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if scrub.state == nil {
                    let pressedTime = CueMarkersGeometry.time(
                        forX: value.startLocation.x,
                        width: width,
                        duration: duration
                    )
                    switch TimelineScrubOrchestrator.begin(
                        pressedTime: pressedTime,
                        isPlaying: engine.isPlaying
                    ) {
                    case .startScrubAndPause(let originalTime):
                        scrub.begin(originalTime: originalTime, isPlaying: true)
                        engine.pause()
                    case .startScrub(let originalTime):
                        scrub.begin(originalTime: originalTime, isPlaying: false)
                    }
                    NSCursor.closedHand.set()
                }
                scrub.update(dx: value.translation.width, width: width, duration: duration)
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                guard let finished = scrub.end() else { return }
                let effect = TimelineScrubOrchestrator.end(finished: finished)
                seekTask?.cancel()
                seekTask = Task {
                    await engine.seek(to: effect.seekTo)
                    if Task.isCancelled { return }
                    if effect.resume {
                        engine.play()
                    }
                }
            }
    }
}
