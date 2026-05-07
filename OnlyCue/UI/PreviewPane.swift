import AVFoundation
import SwiftUI

struct PreviewPane: View {

    let engine: PlayerEngine
    let media: MediaReference?

    var body: some View {
        ZStack {
            Color.black.opacity(0.05)
            content
        }
        .frame(minHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("previewPane")
    }

    @ViewBuilder
    private var content: some View {
        if let media {
            switch media.kind {
            case .video:
                AVPlayerLayerView(player: engine.player)
                    .accessibilityIdentifier("videoPreview")
            case .audio:
                audioContent
            }
        } else {
            placeholder("Import audio or video to preview")
                .accessibilityIdentifier("emptyPreview")
        }
    }

    @ViewBuilder
    private var audioContent: some View {
        if let asset = engine.player.currentItem?.asset as? AVURLAsset {
            WaveformContainer(asset: asset)
                .accessibilityIdentifier("audioWaveform")
        } else {
            placeholder("Audio loaded — reopen with media to see waveform")
                .accessibilityIdentifier("audioPlaceholder")
        }
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
    }
}
