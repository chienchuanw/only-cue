import SwiftUI

/// Document-scoped editor for the project's SMPTE framerate and start timecode
/// (`ProjectModel.timecodeSettings`) — the values the LTC generator reads.
/// Reachable via `Tools → Timecode Settings…` (notification → `DocumentView`
/// presents this sheet). Edits route through `CueCommands.setProjectTimecodeSettings`
/// (undoable). The *Audio* side of LTC (output device + per-channel routing)
/// is a separate, later pane.
struct TimecodeSettingsSheet: View {

    @ObservedObject var document: CueListDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var framerate: SMPTEFramerate
    @State private var startText: String
    @State private var startInvalid = false

    init(document: CueListDocument) {
        self.document = document
        let settings = document.model.timecodeSettings
        _framerate = State(initialValue: settings.framerate)
        _startText = State(initialValue: settings.startTimecode.displayString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Timecode Settings")
                .font(.headline)
            Divider()
            Form {
                Picker("Framerate", selection: $framerate) {
                    ForEach(SMPTEFramerate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .accessibilityIdentifier("timecodeFrameratePicker")
                .onChange(of: framerate) { _, _ in commit() }

                TextField("Start timecode", text: $startText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 160)
                    .onSubmit { commit() }
                    .accessibilityIdentifier("timecodeStartField")

                if startInvalid {
                    Text("Enter a timecode as HH:MM:SS:FF — use ; before the frames for drop-frame.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    commit()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
        .accessibilityIdentifier("timecodeSettingsSheet")
    }

    /// Apply the current picker + (parsed) text to the document. Invalid text is
    /// flagged and left as-is rather than applied; valid text is canonicalised.
    private func commit() {
        guard let start = Timecode.parse(startText, rate: framerate) else {
            startInvalid = true
            return
        }
        startInvalid = false
        startText = start.displayString
        CueCommands.setProjectTimecodeSettings(
            ProjectTimecodeSettings(framerate: framerate, startOffsetFrames: start.frameCount),
            document: document,
            undoManager: undoManager
        )
    }
}

/// Hosts the Timecode Settings sheet on a view: presents it when `Tools →
/// Timecode Settings…` posts `.timecodeSettingsRequested`. Mirrors the
/// `.exportSheet(...)` / `.oscServerHost(...)` host-modifier pattern so
/// `DocumentView`'s body stays under the `type_body_length` cap.
private struct TimecodeSettingsSheetHost: ViewModifier {
    let document: CueListDocument
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .timecodeSettingsRequested)) { _ in
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                TimecodeSettingsSheet(document: document)
            }
    }
}

extension View {
    func timecodeSettingsSheet(document: CueListDocument) -> some View {
        modifier(TimecodeSettingsSheetHost(document: document))
    }
}
