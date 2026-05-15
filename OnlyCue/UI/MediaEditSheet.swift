import SwiftUI

/// Modal sheet for editing a single `MediaItem`'s user-facing metadata:
/// alternate display name, start-timecode offset, and per-clip LTC mute. Save
/// commits all three fields atomically through `CueCommands.updateMediaItem`
/// (single undo step). Cancel discards drafts.
///
/// The TC field uses the project framerate for parsing and display, matching
/// `MediaTimecodeRow`. Per-media framerate is intentionally out of scope.
struct MediaEditSheet: View {

    let item: MediaItem
    let framerate: SMPTEFramerate
    let onSave: (_ alternateName: String?, _ startFrames: Int, _ muted: Bool) -> Void
    let onCancel: () -> Void

    @State private var nameDraft: String = ""
    @State private var tcDraft: String = ""
    @State private var mutedDraft: Bool = false
    @State private var tcInvalid: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Media")
                .font(.headline)

            Form {
                LabeledContent("Name") {
                    TextField(item.media.displayName, text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("mediaEditNameField")
                }
                LabeledContent("Start timecode") {
                    TextField("HH:MM:SS:FF", text: $tcDraft)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(tcInvalid ? Color.red : Color.clear, lineWidth: 1)
                        )
                        .onChange(of: tcDraft) { _, _ in tcInvalid = false }
                        .accessibilityIdentifier("mediaEditStartTimecodeField")
                }
                Toggle("Mute LTC for this clip", isOn: $mutedDraft)
                    .accessibilityIdentifier("mediaEditMuteToggle")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("mediaEditCancel")
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mediaEditSave")
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .onAppear { syncDraftsFromItem() }
    }

    private func syncDraftsFromItem() {
        nameDraft = item.alternateName ?? ""
        tcDraft = Timecode(frameCount: item.startTimecodeFrames, rate: framerate).displayString
        mutedDraft = item.ltcMuted
        tcInvalid = false
    }

    private func commit() {
        guard let parsed = Timecode.parse(tcDraft, rate: framerate) else {
            tcInvalid = true
            return
        }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternate = trimmed.isEmpty ? nil : trimmed
        onSave(alternate, parsed.frameCount, mutedDraft)
    }
}
