import SwiftUI

/// Settings → Keyboard pane: a row per `KeymapAction` showing its current
/// chord, a "record a new shortcut" affordance (Esc cancels), a per-row
/// reset-to-default button, and a Reset-All button. Conflicting chords (two
/// actions on the same combination) are flagged — advisory only; nothing is
/// blocked, matching ADR-018. Rebinds persist immediately via `KeymapStore`.
struct KeyboardSettingsView: View {

    @ObservedObject private var store = KeymapStore.shared
    @State private var recording: KeymapAction?
    @FocusState private var captureFocused: Bool

    private var keymap: Keymap { store.keymap }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(KeymapAction.allCases) { row(for: $0) }
                } header: {
                    Text("Click a shortcut to record a new key combination. Press Esc to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 440)
        .accessibilityIdentifier("keyboardSettings")
        .onChange(of: recording) { _, newValue in
            captureFocused = newValue != nil
        }
    }

    @ViewBuilder
    private func row(for action: KeymapAction) -> some View {
        let chord = keymap.chord(for: action)
        let conflicting = keymap.actionsConflicting(with: chord, excluding: action)
        let isDefault = chord == Keymap.default.chord(for: action)
        HStack(spacing: 8) {
            Text(action.displayName)
            if !conflicting.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Also used by: " + conflicting.map(\.displayName).joined(separator: ", "))
            }
            Spacer(minLength: 8)
            chordControl(for: action, chord: chord)
            Button {
                store.resetToDefault(action)
                if recording == action { recording = nil }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(isDefault)
            .help("Reset to default (\(Keymap.default.chord(for: action).displayString))")
        }
    }

    @ViewBuilder
    private func chordControl(for action: KeymapAction, chord: KeyChord) -> some View {
        if recording == action {
            Text("Press a shortcut…")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tint))
                .focusable()
                .focused($captureFocused)
                .onAppear { captureFocused = true }
                .onKeyPress(phases: .down) { handleKeyPress($0, for: action) }
                .accessibilityIdentifier("keymapCaptureField")
        } else {
            Button {
                recording = action
            } label: {
                Text(chord.displayString)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 56)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("keymapChord.\(action.rawValue)")
        }
    }

    private var footer: some View {
        let conflictCount = keymap.conflicts().count
        return HStack {
            if conflictCount > 0 {
                Label(
                    "\(conflictCount) shortcut\(conflictCount == 1 ? "" : "s") used by more than one action",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text("No conflicts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset All…") {
                store.resetAll()
                recording = nil
            }
        }
        .padding(8)
        .accessibilityIdentifier("keymapFooter")
    }

    private func handleKeyPress(_ keyPress: KeyPress, for action: KeymapAction) -> KeyPress.Result {
        let hasRealModifier = keyPress.modifiers.contains(.command)
            || keyPress.modifiers.contains(.shift)
            || keyPress.modifiers.contains(.option)
            || keyPress.modifiers.contains(.control)
        if KeyChord.specialKeyName(for: keyPress.key) == "escape", !hasRealModifier {
            recording = nil
            return .handled
        }
        guard let chord = KeyChord.from(keyEquivalent: keyPress.key, modifiers: keyPress.modifiers) else {
            return .ignored
        }
        store.rebind(action, to: chord)
        recording = nil
        return .handled
    }
}
