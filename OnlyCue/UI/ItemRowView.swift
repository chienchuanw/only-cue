import SwiftUI

struct ItemRowView: View {

    let item: MediaItem
    @Environment(\.projectFramerate) private var framerate

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.resolvedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(TimeFormat.smpte(item.media.duration, rate: framerate))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .accessibilityIdentifier("itemRow")
    }

    private var icon: String {
        switch item.media.kind {
        case .audio: "waveform"
        case .video: "film"
        }
    }
}
