import SwiftUI

struct ItemRowView: View {

    let item: MediaItem
    /// When non-nil, renders an inline pencil button that fires the closure.
    /// Lives on the row (not only in the parent's context menu) so that
    /// XCUITest can drive Edit Media without the flaky right-click chord and
    /// so users get a discoverable affordance. Audit §13.
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: DS.Space.xs / 2) {
                Text(item.resolvedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // The sidebar shows the clip *length* (a duration), so it uses
                // the compact m:ss form, not framerate SMPTE (ADR-028 amendment;
                // Figma 318:1238). The per-media start timecode (a position)
                // stays SMPTE in MediaTimecodeRow / the TC editor.
                Text(TimeFormat.compactDuration(item.media.duration))
                    .font(DS.Text.label)
                    .foregroundStyle(DS.Color.textTertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: DS.Space.xs)
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundStyle(DS.Color.textSecondary)
                        // The raw SF Symbol's hit shape is ~14×14 pt — XCUITest
                        // synthesizes a click at the AX element's center, but
                        // SwiftUI's gesture recognizer needs a comfortable hit
                        // target. Enlarge the hit-test region (and the visual
                        // touch target for real users) via padding +
                        // contentShape on the Image itself, so the Button's
                        // gesture fires reliably.
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Edit Media…")
                .accessibilityLabel("Edit Media")
                .accessibilityIdentifier("inlineEditMedia-\(item.id.uuidString)")
            }
        }
        // SwiftUI's `List { ForEach { … .tag(item.id) } }` wraps every row
        // in an accessibility container that, with a single
        // `.accessibilityIdentifier` on the HStack, collapses the children
        // into a single AX element — `inlineEditMedia-<id>` then becomes
        // unreachable from XCUITest. `.accessibilityElement(children:
        // .contain)` explicitly preserves the children's identifiers
        // beneath the row's own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("itemRow")
    }

    private var icon: String {
        switch item.media.kind {
        case .audio: "waveform"
        case .video: "film"
        }
    }
}
