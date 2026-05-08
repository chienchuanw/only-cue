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
            let displayedTime = scrub.state?.scrubTime ?? engine.currentTime
            let x = CueMarkersGeometry.position(
                forTime: displayedTime,
                width: width,
                duration: duration
            )

            ZStack(alignment: .topLeading) {
                PlayheadOverlay(currentTime: displayedTime, duration: duration)

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: Self.grabberWidth, height: geometry.size.height)
                    .offset(x: x - Self.grabberWidth / 2)
                    .gesture(scrubGesture(width: width))
                    .accessibilityIdentifier("playheadGrabber")
            }
            .onChange(of: displayedTime) { _, _ in maybeAutoFollow() }
        }
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
                }
                scrub.update(dx: value.translation.width, width: width, duration: duration)
            }
            .onEnded { _ in
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
