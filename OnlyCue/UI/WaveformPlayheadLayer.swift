import AppKit
import QuartzCore
import SwiftUI

struct WaveformPlayheadLayer: View {

    let engine: PlayerEngine
    let duration: TimeInterval
    @Binding var scrub: ScrubController
    @Binding var seekTask: Task<Void, Never>?
    var zoom: WaveformZoomController?
    var viewportWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var applyAutoFollow: ((CGFloat, CGFloat) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation) { _ in
                let displayedTime = renderedTime()

                ZStack(alignment: .topLeading) {
                    // Click-to-seek + hold-to-scrub. A zero-translation drag
                    // collapses to a single seek (the click case). A non-zero
                    // drag pauses on press (only if playing), scrubs while
                    // held, and resumes on release if it was playing.
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

                    PlayheadOverlay(currentTime: displayedTime, duration: duration)
                }
                .onChange(of: displayedTime) { _, _ in maybeAutoFollow() }
            }
        }
    }

    private func renderedTime() -> TimeInterval {
        if let scrubTime = scrub.state?.scrubTime { return scrubTime }
        return PlayheadInterpolator.renderedTime(
            observedTime: engine.currentTime,
            observedAt: engine.currentTimeObservedAt,
            now: CACurrentMediaTime(),
            rate: Double(engine.rate),
            duration: duration
        )
    }

    private func maybeAutoFollow() {
        guard let zoom,
              let applyAutoFollow,
              viewportWidth > 0 else { return }
        let target = zoom.autoFollowAdjustment(
            playheadTime: scrub.state?.scrubTime ?? engine.currentTime,
            duration: duration,
            viewportWidth: viewportWidth,
            currentScrollOffset: scrollOffset
        )
        if let target {
            applyAutoFollow(target, viewportWidth)
        }
    }

    private func timelineDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
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
