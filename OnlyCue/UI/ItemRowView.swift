import SwiftUI

struct ItemRowView: View {

    let item: MediaItem
    @Environment(\.projectFramerate) private var framerate

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: DS.Space.xs / 2) {
                Text(item.resolvedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(TimeFormat.smpte(item.media.duration, rate: framerate))
                    .font(DS.Text.label)
                    .foregroundStyle(DS.Color.textTertiary)
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
