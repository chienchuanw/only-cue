import SwiftUI

/// Settings → MIDI pane: send MIDI Timecode to a chosen destination, and pick
/// one input device, then bind any control on it to
/// an OnlyCue action by arming **Learn** on a row and moving that control
/// (generic MIDI-learn — no per-device presets). Bindings persist immediately
/// via `MIDIMapStore`; the incoming stream is intercepted by
/// `MIDILearnSession`, which the document window's `MIDIInputHost` feeds.
///
/// Rows are grouped: continuous targets (faders/knobs, absolute 0–127) first,
/// then the discrete actions worth reaching from a control surface. A control
/// is the key of the map, so re-learning one moves it rather than duplicating.
///
/// The **MTC output** section leads, because it is show-critical configuration
/// rather than a per-show convenience: a destination and a switch, plus a live
/// status row and a test burst so the rig can be proven at setup rather than at
/// showtime. It is independent of LTC — either, both, or neither may run.
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
    @ObservedObject private var mtcStore = MTCOutputStore.shared
    @StateObject private var mtcOutput = MTCOutput()
    @State private var sources: [(uid: String, name: String)] = []
    @State private var destinations: [(uid: String, name: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                mtcSection
                deviceSection
                bindingSection(title: "Faders & knobs",
                               rows: ContinuousTarget.allCases.map { MIDIAction.continuous($0) })
                bindingSection(title: "Buttons",
                               rows: Self.discreteActions.map { MIDIAction.discrete($0) })
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 560)
        .accessibilityIdentifier("midiSettings")
        .onAppear {
            refreshSources()
            refreshDestinations()
        }
    }

    // MARK: - Sections

    private var mtcSection: some View {
        Section {
            Toggle("Send MIDI Timecode", isOn: mtcEnabled)
                .accessibilityIdentifier("mtcEnabledToggle")
            Picker("Destination", selection: mtcDestination) {
                Text("None").tag(String?.none)
                ForEach(destinations, id: \.uid) { destination in
                    Text(destination.name).tag(String?.some(destination.uid))
                }
            }
            .accessibilityIdentifier("mtcDestinationPicker")
            HStack {
                Button("Rescan devices") { refreshDestinations() }
                    .accessibilityIdentifier("mtcRescan")
                Button("Send test timecode") { sendTestTimecode() }
                    .disabled(!mtcStore.settings.isComplete)
                    .help("Send a Full Frame plus a short burst at 01:00:00:00, without loading media")
                    .accessibilityIdentifier("mtcSendTest")
            }
            mtcStatusRow
        } header: {
            Text("Stream timecode to a console or converter. Independent of LTC — "
                 + "either, both, or neither may run. The rate follows the project framerate.")
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .textCase(nil)
        }
    }

    private var mtcStatusRow: some View {
        let state = MTCStatusLabel.state(
            isComplete: mtcStore.settings.isComplete,
            isRunning: mtcOutput.isRunning,
            lastError: mtcOutput.lastError
        )
        return HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(Self.statusTint(state))
            Text(MTCStatusLabel.statusText(
                state: state,
                timecode: mtcOutput.currentTimecode?.displayString,
                lastError: mtcOutput.lastError
            ))
            .font(.caption)
            .foregroundStyle(DS.Color.textSecondary)
        }
        .accessibilityIdentifier("mtcStatus")
    }

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

    /// Like `deviceSelection`, these write through the store rather than binding
    /// to it directly — `MTCOutputStore.settings` is `private(set)`, so every
    /// change must go via `update` to persist.
    private var mtcEnabled: Binding<Bool> {
        Binding(
            get: { mtcStore.settings.isEnabled },
            set: { mtcStore.update(mtcStore.settings.settingEnabled($0)) }
        )
    }

    private var mtcDestination: Binding<String?> {
        Binding(
            get: { mtcStore.settings.destinationUID },
            set: { mtcStore.update(mtcStore.settings.selectingDestination(uid: $0)) }
        )
    }

    private func refreshDestinations() {
        destinations = MTCOutput.availableDestinations()
    }

    /// Prove the rig at setup: one Full Frame plus a short quarter-frame burst
    /// at 01:00:00:00, with no media loaded and the transport stopped. Also the
    /// documented manual verification step for the CoreMIDI edge.
    private func sendTestTimecode() {
        let rate = ProjectTimecodeSettings.default.framerate
        guard let timecode = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: rate) else { return }
        mtcOutput.sendTestTimecode(at: timecode, destinationUID: mtcStore.settings.destinationUID)
    }

    static func statusTint(_ state: MTCStatusLabel.State) -> Color {
        switch state {
        case .failed:  return .red
        case .sending: return DS.Color.cueIndigo
        case .ready:   return DS.Color.textSecondary
        case .off:     return DS.Color.textSecondary
        }
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
