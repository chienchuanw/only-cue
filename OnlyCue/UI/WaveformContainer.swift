import AVFoundation
import SwiftUI

struct WaveformContainer: View {

    let asset: AVURLAsset
    var resolution: Int = 512

    @State private var peaks: [Float]?
    @State private var failed = false

    var body: some View {
        Group {
            if let peaks {
                WaveformView(peaks: peaks)
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
        let assetCopy = asset

        do {
            let cached: [Float]? = await Task.detached(priority: .userInitiated) {
                guard let hash = try? WaveformCache.fileHash(url) else { return nil }
                return cache.read(assetHash: hash, resolution: target)
            }.value

            if Task.isCancelled { return }
            if let cached {
                peaks = cached
                return
            }

            let generated = try await WaveformGenerator.peaks(for: assetCopy, resolution: target)
            if Task.isCancelled { return }
            peaks = generated

            await Task.detached(priority: .background) {
                guard let hash = try? WaveformCache.fileHash(url) else { return }
                try? cache.write(generated, assetHash: hash, resolution: target)
            }.value
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}
