import SwiftUI

/// Modal sheet for tuning `NotesOverlayPreferences`. Edits a `Binding` so the
/// caller (DocumentView) round-trips the change through the same `@AppStorage`
/// key that `PreviewPane` reads. "Restore Defaults" overwrites every field
/// with `NotesOverlayPreferences.default`.
struct NotesOverlayPreferencesSheet: View {

    @Binding var prefs: NotesOverlayPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Position", selection: $prefs.position) {
                    Text("Top").tag(NotesOverlayPreferences.Position.top)
                    Text("Center").tag(NotesOverlayPreferences.Position.center)
                    Text("Bottom").tag(NotesOverlayPreferences.Position.bottom)
                }
                .pickerStyle(.segmented)

                LabeledContent("Font Scale") {
                    HStack {
                        Slider(
                            value: $prefs.fontScale,
                            in: NotesOverlayPreferences.fontScaleRange,
                            step: 0.05
                        )
                        Text(String(format: "%.2f×", prefs.fontScale))
                            .font(.caption.monospacedDigit())
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Section("Color") {
                ColorPicker("Text Color", selection: textColorBinding, supportsOpacity: false)

                Toggle("Solid Background", isOn: backgroundEnabledBinding)
                if prefs.backgroundColorHex != nil {
                    ColorPicker("Background Color", selection: backgroundColorBinding, supportsOpacity: false)
                }
            }

            Section("Content") {
                Toggle("Show Cue Number Prefix", isOn: $prefs.showCueIDPrefix)
            }

            Section {
                Button("Restore Defaults", role: .destructive) {
                    prefs = .default
                }
                // Audit §11.7: Figma renders this as an outlined secondary
                // pill (panel-tinted with `color/border-strong` stroke), not
                // a red-destructive button. `.bordered` style gives the
                // outlined look; the `.destructive` role is preserved so
                // VoiceOver still reads the action as a reset.
                .buttonStyle(.bordered)
                .accessibilityIdentifier("notesOverlayRestoreDefaults")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 380)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .navigationTitle("Note Overlay Appearance")
        .accessibilityIdentifier("notesOverlayPreferencesSheet")
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: prefs.textColorHex) ?? .white },
            set: { newValue in
                if let hex = newValue.toHex() {
                    prefs.textColorHex = hex
                }
            }
        )
    }

    private var backgroundEnabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.backgroundColorHex != nil },
            set: { enabled in
                prefs.backgroundColorHex = enabled ? "#000000" : nil
            }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { prefs.backgroundColorHex.flatMap(Color.init(hex:)) ?? .black },
            set: { newValue in
                if let hex = newValue.toHex() {
                    prefs.backgroundColorHex = hex
                }
            }
        )
    }
}
