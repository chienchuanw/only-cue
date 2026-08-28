import SwiftUI

struct ItemRowView: View {

    let item: MediaItem
    /// When non-nil, renders an inline pencil button that fires the closure.
    /// Lives on the row (not only in the parent's context menu) so that
    /// XCUITest can drive Edit Media without the flaky right-click chord and
    /// so users get a discoverable affordance. Audit §13.
    var onEdit: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        // Single horizontal line (Figma 318:1238 / component 77:43): leading
        // kind icon · file name (fills, tail-truncates) · clip length · the
        // hover-only edit pencil — never a stacked name-over-duration column.
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: ItemRowMetrics.iconSize)
            Text(item.resolvedName)
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // A song with remembered LTC (#754) gets a compact trailing tag, so
            // the operator sees at a glance which clips carry timecode.
            if item.rememberedLTC != nil {
                Text("LTC")
                    .font(DS.Text.monoLabel)
                    .foregroundStyle(DS.Color.textSecondary)
                    .accessibilityIdentifier("itemRowLTC")
            }
            // The sidebar shows the clip *length* (a duration), so it uses the
            // compact m:ss form, not framerate SMPTE (ADR-028 amendment; Figma
            // 318:1238). The per-media start timecode (a position) stays SMPTE
            // in MediaTimecodeRow / the TC editor.
            Text(TimeFormat.compactDuration(item.media.duration))
                .font(DS.Text.monoLabel)
                .foregroundStyle(DS.Color.textTertiary)
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
                // Hidden at rest, fades in on hover (Figma Hovered variant).
                // Opacity — not `if`/`.hidden()` — keeps the row from reflowing
                // and keeps the AX element reachable for the existing UI tests.
                .opacity(ItemRowMetrics.pencilOpacity(isHovered: isHovered))
            }
        }
        // Reserved on every row so tagging never shifts the text sideways —
        // see `ItemRowMetrics.colorGutter`.
        .padding(.leading, ItemRowMetrics.colorGutter)
        // The user's colour tag (#782), same idiom as the cue list's type
        // stripe. Deliberately *unlike* `CueRowView`, an untagged row draws
        // nothing rather than falling back to `DS.Color.border`: in the cue
        // list having a type is the normal state, here having a colour is the
        // exception, and a grey stripe on every untagged row would stop the
        // tagged ones from standing out at all.
        .overlay(alignment: .leading) {
            if let stripeColor {
                Rectangle()
                    .fill(stripeColor)
                    .frame(width: ItemRowMetrics.colorStripeWidth)
                    .accessibilityIdentifier("itemRowSwatch-\(item.id.uuidString)")
                    .accessibilityLabel(colorLabel)
            }
        }
        .onHover { isHovered = $0 }
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

    /// The tag colour, or nil when the clip is untagged — or when a hand-edited
    /// `.cuelist` carries an unparseable hex, which degrades to untagged rather
    /// than to a wrong colour.
    private var stripeColor: Color? {
        item.colorHex.flatMap { Color(hex: $0) }
    }

    /// Names the colour for VoiceOver, so the tag is perceivable without colour
    /// vision. Falls back to the raw hex for a value outside the palette.
    private var colorLabel: Text {
        guard let hex = item.colorHex else { return Text(verbatim: "") }
        guard let name = CuePointType.paletteName(forHex: hex) else { return Text(verbatim: hex) }
        return Text(name)
    }
}
