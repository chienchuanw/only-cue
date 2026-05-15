import AppKit
import QuartzCore
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
/// A zero-translation drag collapses to a single seek (the click case).
/// A non-zero drag pauses on press (only if the engine is playing),
/// scrubs while held, and resumes on release if it was playing — see
/// `TimelineScrubOrchestrator`.
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
                .gesture(timelineDragGesture(width: width))
                .onContinuousHover { phase in
                    switch phase {
                    case .active: NSCursor.openHand.set()
                    case .ended: NSCursor.arrow.set()
                    }
                }
                .accessibilityIdentifier("waveformSeekSurface")
        }
    }

    private func timelineDragGesture(width: CGFloat) -> some Gesture {
        // minimumDistance: 1 lets a marker's `DragGesture(minimumDistance: 0)`
        // win arbitration when the press lands on a cap. Click-to-seek still
        // works because the seek surface's gesture collapses zero-translation
        // drags to a single seek (`TimelineScrubOrchestrator.end`).
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
