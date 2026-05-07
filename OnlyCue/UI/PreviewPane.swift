import SwiftUI

struct PreviewPane: View {

    enum Kind: Equatable {
        case empty
        case audio
        case video
    }

    let engine: PlayerEngine
    let media: MediaReference?

    static func previewKind(for media: MediaReference?) -> Kind {
        guard let media else { return .empty }
        switch media.kind {
        case .audio: return .audio
        case .video: return .video
        }
    }

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
        switch Self.previewKind(for: media) {
        case .video:
            AVPlayerLayerView(player: engine.player)
                .accessibilityIdentifier("videoPreview")
        case .audio:
            placeholder("Audio loaded — waveform arrives in E5")
                .accessibilityIdentifier("audioPlaceholder")
        case .empty:
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
