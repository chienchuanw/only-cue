import AVFoundation
import SwiftUI

struct WaveformContainer: View {

    let asset: AVURLAsset
    var resolution: Int = 512
    var cues: [Cue] = []
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }
    var showsPlayhead: Bool = false
    var engine: PlayerEngine?

    @State private var peaks: [Float]?
    @State private var failed = false
    @State private var loadedDuration: TimeInterval = 0
    @State private var scrub = ScrubController()

    private static let grabberWidth: CGFloat = 12

    var body: some View {
        Group {
            if let peaks {
                WaveformView(peaks: peaks)
                    .overlay(alignment: .topLeading) { playheadLayer }
                    .overlay(alignment: .topLeading) {
                        if loadedDuration > 0 {
                            CueMarkersOverlay(
                                cues: cues,
                                duration: loadedDuration,
                                onSeek: onSeek,
                                onRetime: onRetime
                            )
                        }
                    }
                    .overlay(alignment: .topLeading) { grabberLayer }
                    .padding(.horizontal, 8)
            } else if failed {
                Text("Could not generate waveform")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("waveformLoading")
            }
        }
        .task(id: asset.url) { await load() }
    }

    @ViewBuilder
    private var playheadLayer: some View {
        if showsPlayhead, let engine, loadedDuration > 0 {
            PlayheadOverlay(
                currentTime: scrub.state?.scrubTime ?? engine.currentTime,
                duration: loadedDuration
            )
        }
    }

    @ViewBuilder
    private var grabberLayer: some View {
        if showsPlayhead, let engine, loadedDuration > 0 {
            GeometryReader { geometry in
                let displayedTime = scrub.state?.scrubTime ?? engine.currentTime
                let x = CueMarkersGeometry.position(
                    forTime: displayedTime,
                    width: geometry.size.width,
                    duration: loadedDuration
                )
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: Self.grabberWidth, height: geometry.size.height)
                    .offset(x: x - Self.grabberWidth / 2)
                    .gesture(scrubGesture(width: geometry.size.width, engine: engine))
                    .accessibilityIdentifier("playheadGrabber")
            }
        }
    }

    private func scrubGesture(width: CGFloat, engine: PlayerEngine) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrub.state == nil {
                    scrub.begin(originalTime: engine.currentTime, isPlaying: engine.rate > 0)
                    engine.pause()
                }
                scrub.update(dx: value.translation.width, width: width, duration: loadedDuration)
            }
            .onEnded { _ in
                guard let finished = scrub.end() else { return }
                Task {
                    await engine.seek(to: finished.scrubTime)
                    if finished.resumeOnRelease {
                        engine.play()
                    }
                }
            }
    }

    private func load() async {
        peaks = nil
        failed = false
        let cache = WaveformCache.shared
        let target = resolution
        let url = asset.url

        do {
            let hash: String? = await Task.detached(priority: .userInitiated) {
                try? WaveformCache.fileHash(url)
            }.value

            if Task.isCancelled { return }

            let cmDuration = try await asset.load(.duration)
            loadedDuration = CMTimeGetSeconds(cmDuration)

            if let hash, let cached = cache.read(assetHash: hash, resolution: target) {
                peaks = cached
                return
            }

            let generated = try await WaveformGenerator.peaks(for: asset, resolution: target)
            if Task.isCancelled { return }
            peaks = generated

            if let hash {
                Task.detached(priority: .background) {
                    try? cache.write(generated, assetHash: hash, resolution: target)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}
