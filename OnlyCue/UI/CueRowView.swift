import SwiftUI

struct CueRowView: View {

    let index: Int
    let cue: Cue
    var resolvedColorHex: String?
    var onRename: (String) -> Void = { _ in }

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            CueColorSwatch(hex: resolvedColorHex, diameter: 14)
                .accessibilityIdentifier("cueColorSwatch-\(index)")

            nameField
                .accessibilityIdentifier("cueName-\(index)")

            Spacer(minLength: 8)

            Text(TimeFormat.hms(cue.time))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("cueRow-\(index)")
    }

    @ViewBuilder
    private var nameField: some View {
        if isEditingName {
            TextField("Cue name", text: $draftName)
                .textFieldStyle(.plain)
                .focused($nameFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { cancelRename() }
                .onAppear { nameFieldFocused = true }
        } else {
            Text(cue.name.isEmpty ? "Untitled" : cue.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { beginRename() }
        }
    }

    private func beginRename() {
        draftName = cue.name
        isEditingName = true
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != cue.name {
            onRename(trimmed)
        }
        isEditingName = false
    }

    private func cancelRename() {
        isEditingName = false
    }
}
