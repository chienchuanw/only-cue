import SwiftUI

struct ItemRowView: View {

    let item: MediaItem
    /// When non-nil, renders an inline pencil button that fires the closure.
    /// Lives on the row (not only in the parent's context menu) so that
    /// XCUITest can drive Edit Media without the flaky right-click chord and
    /// so users get a discoverable affordance. Audit §13.
    var onEdit: (() -> Void)?
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
            Spacer(minLength: DS.Space.xs)
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("Edit Media…")
                .accessibilityLabel("Edit Media")
                .accessibilityIdentifier("inlineEditMedia-\(item.id.uuidString)")
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
