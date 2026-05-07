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
        if let media = document.model.media {
            switch media.kind {
            case .video:
                videoContent
            case .audio:
                audioContent
            }
        } else {
            placeholder("Import audio or video to preview")
                .accessibilityIdentifier("emptyPreview")
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        if let asset = engine.player.currentItem?.asset as? AVURLAsset {
            VStack(spacing: 0) {
                videoPlayer
                waveform(for: asset)
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
    private var audioContent: some View {
        if let asset = engine.player.currentItem?.asset as? AVURLAsset {
            waveform(for: asset)
                .accessibilityIdentifier("audioWaveform")
        } else {
            placeholder("Audio loaded — reopen with media to see waveform")
                .accessibilityIdentifier("audioPlaceholder")
        }
    }

    private func waveform(for asset: AVURLAsset) -> WaveformContainer {
        WaveformContainer(
            asset: asset,
            cues: document.model.cues,
            onSeek: { time in Task { await engine.seek(to: time) } },
            onRetime: { cueId, newTime in
                CueCommands.retime(
                    cueId: cueId,
                    to: newTime,
                    document: document,
                    undoManager: undoManager
                )
            }
        )
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
    }
}
