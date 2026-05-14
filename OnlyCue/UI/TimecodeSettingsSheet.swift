import SwiftUI

/// Document-scoped editor for the project framerate and per-media start
/// timecode. Schema v10 lifted the start TC out of the project and onto each
/// `MediaItem`; this sheet exposes both: the framerate picker at the top, and
/// a list of every media item with an editable HH:MM:SS:FF field below.
/// Reachable via `Tools → Timecode Settings…`.
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
                .onChange(of: framerate) { _, _ in commitFramerate() }

                if !document.model.items.isEmpty {
                    Section("Media start timecodes") {
                        ForEach(document.model.items) { item in
                            MediaTimecodeRow(
                                item: item,
                                framerate: framerate,
                                onCommit: { frames in commitStartTimecode(itemID: item.id, frames: frames) }
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("timecodeSheetItemList")

            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460)
        .accessibilityIdentifier("timecodeSettingsSheet")
    }

    private func commitFramerate() {
        CueCommands.setProjectTimecodeSettings(
            ProjectTimecodeSettings(framerate: framerate),
            document: document,
            undoManager: undoManager
        )
    }

    private func commitStartTimecode(itemID: MediaItem.ID, frames: Int) {
        CueCommands.setStartTimecode(
            itemID: itemID,
            frames: frames,
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
