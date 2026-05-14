import SwiftUI

/// A single row in `TimecodeSettingsSheet`'s "Media start timecodes" list: file
/// name + editable `HH:MM:SS:FF` field. Parses via `Timecode.parse`; invalid
/// input outlines the field red and does not commit. The row owns a local
/// `draft` so the user's in-progress typing isn't clobbered by upstream
/// `MediaItem` mutations (each commit goes through `CueCommands` and replaces
/// the bound `item`).
struct MediaTimecodeRow: View {

    let item: MediaItem
    let framerate: SMPTEFramerate
    let onCommit: (Int) -> Void

    @State private var draft: String = ""
    @State private var isInvalid: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.media.kind == .video ? "video" : "music.note")
                .foregroundStyle(.secondary)
            Text(item.media.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            TextField("HH:MM:SS:FF", text: $draft)
                .font(.body.monospaced())
                .frame(width: 110)
                .multilineTextAlignment(.trailing)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isInvalid ? Color.red : Color.clear, lineWidth: 1)
                )
                .onSubmit { commit() }
                .accessibilityIdentifier("startTimecodeField")
        }
        .onAppear { syncDraftFromItem() }
        .onChange(of: item.startTimecodeFrames) { _, _ in syncDraftFromItem() }
        .onChange(of: framerate) { _, _ in syncDraftFromItem() }
    }

    private func syncDraftFromItem() {
        draft = Timecode(frameCount: item.startTimecodeFrames, rate: framerate).displayString
        isInvalid = false
    }

    private func commit() {
        if let parsed = Timecode.parse(draft, rate: framerate) {
            isInvalid = false
            draft = parsed.displayString
            onCommit(parsed.frameCount)
        } else {
            isInvalid = true
        }
    }
}
