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
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Media")
                .font(.headline)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            MediaPreviewStrip(
                kind: item.media.kind,
                bookmarkData: item.media.bookmarkData
            )

            HStack(spacing: 8) {
                Image(systemName: item.media.kind == .audio ? "waveform" : "film")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.media.displayName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.media.kind == .audio ? "Audio" : "Video") · "
                         + TimeFormat.smpte(item.media.duration, rate: framerate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .accessibilityIdentifier("mediaEditIdentity")

            Divider()

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
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("mediaEditCancel")
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mediaEditSave")
            }
            .padding(20)
        }
        .frame(width: 460)
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
