import SwiftUI

/// Document-scoped editor for the project's SMPTE framerate. As of schema v10
/// each `MediaItem` carries its own `startTimecodeFrames`; this sheet only
/// edits the project-wide framerate. The per-media start TC editor is added
/// in a later leaf. Reachable via `Tools → Timecode Settings…`.
struct TimecodeSettingsSheet: View {

    @ObservedObject var document: CueListDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var framerate: SMPTEFramerate

    init(document: CueListDocument) {
        self.document = document
        _framerate = State(initialValue: document.model.timecodeSettings.framerate)
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

    private func commit() {
        CueCommands.setProjectTimecodeSettings(
            ProjectTimecodeSettings(framerate: framerate),
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
