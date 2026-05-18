import AVFoundation
import SwiftUI

/// Hero preview for the Edit Media sheet. Audio -> reused `WaveformView`;
/// video -> `VideoPosterGenerator` frame; stale/missing/failed -> kind-icon
/// fallback. Fixed height, full width, neutral background.
struct MediaPreviewStrip: View {

    let kind: MediaKind
    let bookmarkData: Data
    var height: CGFloat = 72

    private static let waveformResolution = 1_200
    private static let posterMaxPixelSize: CGFloat = 512

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
            .accessibilityIdentifier("mediaEditPreviewStrip")
    }

    @ViewBuilder
    private var content: some View {
        switch MediaPreviewPlan.make(kind: kind, bookmarkData: bookmarkData) {
        case .waveform(let url):
            WaveformPreview(url: url, resolution: Self.waveformResolution, fallback: fallback)
        case .poster(let url):
            VideoPosterPreview(url: url, maxPixelSize: Self.posterMaxPixelSize, fallback: fallback)
        case .unavailable:
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: kind == .audio ? "waveform" : "film")
            .font(.system(size: 28))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Loads (cache -> generate -> cache) and renders an audio waveform at a
/// modal-sized resolution. Reuses `WaveformCache`/`WaveformGenerator`.
private struct WaveformPreview<Fallback: View>: View {
    let url: URL
    let resolution: Int
    let fallback: Fallback

    @State private var peaks: [Float]?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                fallback
            } else if let peaks {
                WaveformView(peaks: peaks)
                    .padding(.vertical, 6)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let hash = try? WaveformCache.fileHash(url) else { failed = true; return }
        if let cached = WaveformCache.shared.read(assetHash: hash, resolution: resolution) {
            peaks = cached
            return
        }
        do {
            let generated = try await WaveformGenerator.peaks(
                for: AVURLAsset(url: url), resolution: resolution
            )
            try? WaveformCache.shared.write(generated, assetHash: hash, resolution: resolution)
            peaks = generated
        } catch {
            failed = true
        }
    }
}

/// Loads (cache -> generate -> cache) and renders a video poster frame.
private struct VideoPosterPreview<Fallback: View>: View {
    let url: URL
    let maxPixelSize: CGFloat
    let fallback: Fallback

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                fallback
            } else if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let hash = try? WaveformCache.fileHash(url) else { failed = true; return }
        let sizeKey = Int(maxPixelSize)
        if let cached = VideoPosterCache.shared.read(assetHash: hash, maxPixelSize: sizeKey) {
            image = cached
            return
        }
        do {
            let generated = try await VideoPosterGenerator.poster(
                for: AVURLAsset(url: url), maxPixelSize: maxPixelSize
            )
            try? VideoPosterCache.shared.write(generated, assetHash: hash, maxPixelSize: sizeKey)
            image = generated
        } catch {
            failed = true
        }
    }
}
