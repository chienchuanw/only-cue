import SwiftUI

struct ItemRowView: View {

    let item: MediaItem
    var framerate: SMPTEFramerate = .fps30
    var onSetStartTimecode: (Int) -> Void = { _ in }

    @State private var isEditingStartTimecode = false
    @State private var draftStartTimecode: String = ""
    @State private var draftIsInvalid: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.resolvedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(TimeFormat.hms(item.media.duration))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .accessibilityIdentifier("itemRow")
        .contextMenu {
            Button("Set start timecode…") {
                draftStartTimecode = Timecode(frameCount: item.startTimecodeFrames, rate: framerate).displayString
                draftIsInvalid = false
                isEditingStartTimecode = true
            }
        }
        .popover(isPresented: $isEditingStartTimecode, arrowEdge: .trailing) {
            inlineStartTimecodeEditor
        }
    }

    private var icon: String {
        switch item.media.kind {
        case .audio: "waveform"
        case .video: "film"
        }
    }

    private var inlineStartTimecodeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start timecode")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("HH:MM:SS:FF", text: $draftStartTimecode)
                .font(.body.monospaced())
                .frame(width: 140)
                .multilineTextAlignment(.trailing)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(draftIsInvalid ? Color.red : Color.clear, lineWidth: 1)
                )
                .onSubmit { commitDraft() }
                .accessibilityIdentifier("inlineStartTimecodeField")
            HStack {
                Button("Cancel") { isEditingStartTimecode = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { commitDraft() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func commitDraft() {
        guard let parsed = Timecode.parse(draftStartTimecode, rate: framerate) else {
            draftIsInvalid = true
            return
        }
        onSetStartTimecode(parsed.frameCount)
        isEditingStartTimecode = false
    }
}
