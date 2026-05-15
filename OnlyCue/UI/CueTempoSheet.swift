import SwiftUI

/// Modal sheet for editing a single cue's tempo (BPM + beats-per-bar) and
/// optionally running spectral-flux tempo detection on the cue's media
/// window. Save commits via `CueCommands.setCueTempo` through the host's
/// `onSave` callback — atomic, single undo step. Detect populates the BPM
/// draft via `CueTempoCommit.formatDetectedBPM` but never commits on its
/// own: the user must press Save.
struct CueTempoSheet: View {

    typealias DetectResult = (bpm: Double, message: String?)

    let cueLabel: String
    let initialBPM: Double?
    let initialBeatsPerBar: Int?
    let onDetect: (_ beatsPerBar: Int) async -> DetectResult?
    let onSave: (_ bpm: Double?, _ beatsPerBar: Int?) -> Void
    let onCancel: () -> Void

    @State private var bpmDraft: String
    @State private var beatsPerBarDraft: String
    @State private var statusMessage: String?
    @State private var isDetecting: Bool = false

    init(
        cueLabel: String,
        initialBPM: Double?,
        initialBeatsPerBar: Int?,
        onDetect: @escaping (_ beatsPerBar: Int) async -> DetectResult?,
        onSave: @escaping (_ bpm: Double?, _ beatsPerBar: Int?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cueLabel = cueLabel
        self.initialBPM = initialBPM
        self.initialBeatsPerBar = initialBeatsPerBar
        self.onDetect = onDetect
        self.onSave = onSave
        self.onCancel = onCancel
        self._bpmDraft = State(initialValue: initialBPM.map { String(Int($0.rounded())) } ?? "")
        self._beatsPerBarDraft = State(initialValue: initialBeatsPerBar.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tempo — \(cueLabel)")
                .font(.headline)

            Form {
                LabeledContent("BPM") {
                    TextField("inherited", text: $bpmDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .accessibilityIdentifier("cueTempoSheetBPM")
                }
                LabeledContent("Beats / bar") {
                    TextField("4", text: $beatsPerBarDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .accessibilityIdentifier("cueTempoSheetBeatsPerBar")
                }
            }

            HStack(spacing: 8) {
                Button("Detect") { Task { await runDetect() } }
                    .disabled(isDetecting)
                    .accessibilityIdentifier("cueTempoSheetDetect")
                Button("Clear") { clear() }
                    .accessibilityIdentifier("cueTempoSheetClear")
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("cueTempoSheetStatus")
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cueTempoSheetCancel")
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("cueTempoSheetSave")
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .accessibilityIdentifier("cueTempoSheet")
    }

    private func clear() {
        bpmDraft = ""
        beatsPerBarDraft = ""
        statusMessage = nil
    }

    private func runDetect() async {
        isDetecting = true
        defer { isDetecting = false }
        let beats = Int(beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? initialBeatsPerBar
            ?? 4
        if let outcome = await onDetect(beats) {
            bpmDraft = CueTempoCommit.formatDetectedBPM(outcome.bpm)
            statusMessage = outcome.message
        } else {
            statusMessage = "No tempo detected."
        }
    }

    private func commit() {
        let resolved = CueTempoCommit.resolve(
            bpmDraft: bpmDraft,
            beatsPerBarDraft: beatsPerBarDraft,
            initialBPM: initialBPM,
            initialBeatsPerBar: initialBeatsPerBar
        )
        onSave(resolved.bpm, resolved.beatsPerBar)
    }

    // MARK: - Test hooks
    //
    // @State writes pre-hosting are no-ops, so behavioural tests target
    // CueTempoCommit and these closure-based hooks (cancel + the no-arg
    // commit path through the sheet's initial draft state).
    func testCommit() { commit() }
    func testCancel() { onCancel() }
    /// Invokes the same detect pipeline used by the Detect button. Returns
    /// the formatted BPM string (if detection produced one) so tests can
    /// assert the format without relying on @State propagation.
    func testRunDetect() async -> String? {
        let beats = Int(beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? initialBeatsPerBar
            ?? 4
        if let outcome = await onDetect(beats) {
            return CueTempoCommit.formatDetectedBPM(outcome.bpm)
        }
        return nil
    }
}
