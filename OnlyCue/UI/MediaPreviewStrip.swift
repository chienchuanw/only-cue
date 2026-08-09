import AVFoundation
import SwiftUI

/// Hero preview for the Edit Media sheet. Audio -> reused `WaveformView`;
/// video -> `VideoPosterGenerator` frame; stale/missing/failed -> kind-icon
/// fallback. Fixed height, full width, neutral background.
struct MediaPreviewStrip: View {

    let kind: MediaKind
    let bookmarkData: Data
    /// The detected LTC channel index to omit from the audio waveform so the
    /// preview shows music only (#715/#720), mirroring `WaveformContainer`. nil
    /// when no LTC is detected → byte-identical to the all-channel downmix.
    var excludingChannel: Int?
    var height: CGFloat = 72

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
            WaveformPreview(
                url: url,
                bucketMillis: WaveformGenerator.defaultBucketMillis,
                excludingChannel: excludingChannel,
                fallback: fallback
            )
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

/// Loads (cache -> generate -> cache) and renders an audio waveform with the
/// dual envelope. Shares the v4 bucket cache with `WaveformContainer` — same
/// hash + `bucketMillis` + exclusion key — so the modal preview and the main
/// timeline never decode the same file twice.
private struct WaveformPreview<Fallback: View>: View {
    let url: URL
    let bucketMillis: Int
    let excludingChannel: Int?
    let fallback: Fallback

    @State private var buckets: [WaveformBucket]?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                fallback
            } else if let buckets {
                WaveformView(buckets: buckets)
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
        guard let hash = try? WaveformCache.fastFingerprint(url) else { failed = true; return }
        if let cached = WaveformCache.shared.readBuckets(
            assetHash: hash, bucketMillis: bucketMillis, excludingChannel: excludingChannel
        ) {
            buckets = cached
            return
        }
        do {
            let generated = try await WaveformGenerator.buckets(
                for: AVURLAsset(url: url), bucketMillis: bucketMillis, excludingChannel: excludingChannel
            )
            try? WaveformCache.shared.writeBuckets(
                generated, assetHash: hash, bucketMillis: bucketMillis, excludingChannel: excludingChannel
            )
            buckets = generated
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
        guard let hash = try? WaveformCache.fastFingerprint(url) else { failed = true; return }
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
