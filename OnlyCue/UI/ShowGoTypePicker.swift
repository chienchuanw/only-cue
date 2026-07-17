import SwiftUI

/// Show-mode "GO type" selector (#657) pinned in the cue-list pane's lower area.
/// Picks which cue **type** GO / prev-cue / next-cue / the current-cue highlight
/// walk; the stored value is the type's UUID string, "" = All (walk every cue).
/// Persisted by the caller in the per-window `@SceneStorage("onlycue.showGoTypeID")`,
/// shared with `DocumentView`. Rendered only in Show mode. Its own file keeps
/// `CueListPane` under SwiftLint's `type_body_length` cap.
struct ShowGoTypePicker: View {

    let types: [CuePointType]
    @Binding var selectionRaw: String

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text("GO walks")
                .font(DS.Text.label)
                .foregroundStyle(DS.Color.textTertiary)
            Picker("GO cue type", selection: $selectionRaw) {
                Text("All").tag("")
                ForEach(types) { type in
                    typeLabel(type).tag(type.id.uuidString)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .accessibilityIdentifier("showGoTypePicker")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CueListLayout.rowHorizontalPadding)
        .padding(.vertical, DS.Space.xs)
    }

    /// A colour dot + the type name, so the popup distinguishes types visually
    /// (Figma type-swatch treatment). Falls back to the bare name when the hex
    /// can't be parsed.
    @ViewBuilder
    private func typeLabel(_ type: CuePointType) -> some View {
        if let color = Color(hex: type.colorHex) {
            Label {
                Text(type.name)
            } icon: {
                Circle()
                    .fill(color)
                    .frame(width: CueListLayout.swatchDiameter, height: CueListLayout.swatchDiameter)
            }
        } else {
            Text(type.name)
        }
    }
}
