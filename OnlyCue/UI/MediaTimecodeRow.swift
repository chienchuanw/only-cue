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
        HStack(spacing: DS.Space.sm) {
            Text(item.resolvedName)
                .font(DS.Text.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Space.sm)
            // Bordered HH:MM:SS:FF field (Figma 321:2292) — a sunken box with a
            // hairline border that turns red on invalid input.
            TextField("HH:MM:SS:FF", text: $draft)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xs)
                .frame(width: 110)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.surfaceSunken))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(isInvalid ? Color.red : DS.Color.border, lineWidth: 1)
                )
                .onSubmit { commit() }
                .accessibilityIdentifier("startTimecodeField")
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
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
