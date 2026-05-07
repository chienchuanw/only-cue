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
                placeholder("Audio loaded — waveform arrives in E5")
                    .accessibilityIdentifier("audioPlaceholder")
            }
        } else {
            placeholder("Import audio or video to preview")
                .accessibilityIdentifier("emptyPreview")
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
