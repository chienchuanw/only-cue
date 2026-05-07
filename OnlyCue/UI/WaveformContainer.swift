import AVFoundation
import SwiftUI

struct WaveformContainer: View {

    let asset: AVURLAsset
    var resolution: Int = 512
    var cues: [Cue] = []
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }

    @State private var peaks: [Float]?
    @State private var failed = false
    @State private var loadedDuration: TimeInterval = 0

    var body: some View {
        Group {
            if let peaks {
                WaveformView(peaks: peaks)
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
