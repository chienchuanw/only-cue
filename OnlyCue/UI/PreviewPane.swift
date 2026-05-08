import AVFoundation
import SwiftUI

struct PreviewPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine

    @Environment(\.undoManager) private var undoManager

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
        if let item = document.model.activeItem {
            switch item.media.kind {
            case .video:
                videoContent(item: item)
            case .audio:
                audioContent(item: item)
            }
        } else {
            placeholder("Import audio or video to preview")
                .accessibilityIdentifier("emptyPreview")
        }
    }

    @ViewBuilder
    private func videoContent(item: MediaItem) -> some View {
        if let asset = engine.player.currentItem?.asset as? AVURLAsset {
            VStack(spacing: 0) {
                videoPlayer
                waveform(for: asset, item: item, withPlayhead: true)
                    .frame(height: 100)
                    .accessibilityIdentifier("videoWaveform")
            }
        } else {
            videoPlayer
        }
    }

    private var videoPlayer: some View {
        AVPlayerLayerView(player: engine.player)
            .accessibilityIdentifier("videoPreview")
    }

    @ViewBuilder
    private func audioContent(item: MediaItem) -> some View {
        if let asset = engine.player.currentItem?.asset as? AVURLAsset {
            waveform(for: asset, item: item, withPlayhead: true)
                .accessibilityIdentifier("audioWaveform")
        } else {
            placeholder("Audio loaded — reopen with media to see waveform")
                .accessibilityIdentifier("audioPlaceholder")
        }
    }

    private func waveform(for asset: AVURLAsset, item: MediaItem, withPlayhead: Bool = false) -> some View {
        WaveformContainer(
            asset: asset,
            cues: item.cues,
            onSeek: { time in Task { await engine.seek(to: time) } },
            onRetime: { cueId, newTime in
                CueCommands.retime(
                    cueId: cueId,
                    to: newTime,
                    document: document,
                    undoManager: undoManager
                )
            },
            engine: withPlayhead ? engine : nil
        )
        .id(asset.url)
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
    }
}
