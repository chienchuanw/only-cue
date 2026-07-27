import SwiftUI

/// Settings → MIDI pane: pick one input device, then bind any control on it to
/// an OnlyCue action by arming **Learn** on a row and moving that control
/// (generic MIDI-learn — no per-device presets). Bindings persist immediately
/// via `MIDIMapStore`; the incoming stream is intercepted by
/// `MIDILearnSession`, which the document window's `MIDIInputHost` feeds.
///
/// Rows are grouped: continuous targets (faders/knobs, absolute 0–127) first,
/// then the discrete actions worth reaching from a control surface. A control
/// is the key of the map, so re-learning one moves it rather than duplicating.
struct MIDISettingsView: View {

    /// The discrete actions offered as MIDI targets. Deliberately a curated
    /// subset of `KeymapAction` — the show-calling verbs. The rest stay
    /// keyboard-only in v1 (`MIDIInputHost.applyKeymap` ignores them), so
    /// listing them here would offer bindings that silently do nothing.
    private static let discreteActions: [KeymapAction] = [
        .playPause, .go, .stop, .stepPrevCue, .stepNextCue, .addCue
    ]

    @ObservedObject private var store = MIDIMapStore.shared
    @ObservedObject private var learnSession = MIDILearnSession.shared
    @State private var sources: [(uid: String, name: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                deviceSection
                bindingSection(title: "Faders & knobs",
                               rows: ContinuousTarget.allCases.map { MIDIAction.continuous($0) })
                bindingSection(title: "Buttons",
                               rows: Self.discreteActions.map { MIDIAction.discrete($0) })
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 440)
        .accessibilityIdentifier("midiSettings")
        .onAppear { refreshSources() }
    }

    // MARK: - Sections

    private var deviceSection: some View {
        Section {
            Picker("Input device", selection: deviceSelection) {
                Text("None").tag(String?.none)
                ForEach(sources, id: \.uid) { source in
                    Text(source.name).tag(String?.some(source.uid))
                }
            }
            .accessibilityIdentifier("midiDevicePicker")
            Button("Rescan devices") { refreshSources() }
                .accessibilityIdentifier("midiRescan")
        } header: {
            Text("Choose the surface OnlyCue listens to, then arm Learn on a row "
                 + "and move the control you want to bind.")
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .textCase(nil)
        }
    }

    private func bindingSection(title: String, rows: [MIDIAction]) -> some View {
        Section(title) {
            ForEach(rows, id: \.token) { row(for: $0) }
        }
    }

    @ViewBuilder
    private func row(for action: MIDIAction) -> some View {
        let controls = store.map.controls(for: action)
        HStack(spacing: 8) {
            Text(action.displayName)
            Spacer(minLength: 8)
            Text(Self.boundControlsText(controls))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(controls.isEmpty ? DS.Color.textSecondary : .primary)
                .accessibilityIdentifier("midiBinding.\(action.token)")
            learnButton(for: action)
            Button {
                controls.forEach(store.clear)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .disabled(controls.isEmpty)
            .help("Clear this binding")
            .accessibilityIdentifier("midiClear.\(action.token)")
        }
    }

    @ViewBuilder
    private func learnButton(for action: MIDIAction) -> some View {
        let isLearning = learnSession.target == action
        Button(isLearning ? "Move a control…" : "Learn") {
            if isLearning { learnSession.cancel() } else { learnSession.begin(action) }
        }
        .buttonStyle(.bordered)
        .tint(isLearning ? DS.Color.cueIndigo : nil)
        .accessibilityIdentifier("midiLearn.\(action.token)")
    }

    private var footer: some View {
        HStack {
            Text(Self.learnHintText(target: learnSession.target))
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer()
            Button("Reset All…") {
                store.resetAll()
                learnSession.cancel()
            }
            .accessibilityIdentifier("midiResetAll")
        }
        .padding(8)
        .accessibilityIdentifier("midiFooter")
    }

    // MARK: - Plumbing

    /// The picker writes through the store rather than binding to it directly,
    /// because `selectedInputUID` is `private(set)` — every change must go via
    /// `selectInput` so it persists.
    private var deviceSelection: Binding<String?> {
        Binding(get: { store.selectedInputUID }, set: { store.selectInput(uid: $0) })
    }

    private func refreshSources() {
        sources = MIDIInput.availableSources()
    }

    // MARK: - Pure copy

    /// The bound-control column: the control tokens, or an em dash when the row
    /// is unbound. Two controls may share an action, so this can list several.
    static func boundControlsText(_ controls: [MIDIControlID]) -> String {
        controls.isEmpty ? "—" : controls.map(\.token).sorted().joined(separator: ", ")
    }

    /// Footer hint — names what Learn is waiting for, so an armed row is
    /// obvious even after scrolling away from it.
    static func learnHintText(target: MIDIAction?) -> String {
        guard let target else { return "Not learning" }
        return "Learning · move a control to bind \(target.displayName)"
    }
}
