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

    private static let grabberWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation) { _ in
                let displayedTime = renderedTime()
                let x = CueMarkersGeometry.position(
                    forTime: displayedTime,
                    width: width,
                    duration: duration
                )

                ZStack(alignment: .topLeading) {
                    // Tap anywhere on the waveform body -> seek there immediately.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            seekTask?.cancel()
                            let target = CueMarkersGeometry.time(
                                forX: location.x, width: width, duration: duration
                            )
                            seekTask = Task { await engine.seek(to: target) }
                        }
                        .accessibilityIdentifier("waveformSeekSurface")

                    PlayheadOverlay(currentTime: displayedTime, duration: duration)

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: Self.grabberWidth, height: geometry.size.height)
                        .offset(x: x - Self.grabberWidth / 2)
                        .gesture(scrubGesture(width: width))
                        .onContinuousHover { phase in
                            switch phase {
                            case .active: NSCursor.openHand.set()
                            case .ended: NSCursor.arrow.set()
                            }
                        }
                        .accessibilityIdentifier("playheadGrabber")
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

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrub.state == nil {
                    scrub.begin(originalTime: engine.currentTime, isPlaying: engine.isPlaying)
                    engine.pause()
                    NSCursor.closedHand.set()
                }
                scrub.update(dx: value.translation.width, width: width, duration: duration)
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                guard let finished = scrub.end() else { return }
                seekTask?.cancel()
                seekTask = Task {
                    await engine.seek(to: finished.scrubTime)
                    if Task.isCancelled { return }
                    if finished.resumeOnRelease {
                        engine.play()
                    }
                }
            }
    }
}
