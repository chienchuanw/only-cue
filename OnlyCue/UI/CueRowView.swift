import SwiftUI

struct CueRowView: View {

    let index: Int
    let cue: Cue
    var onRename: (String) -> Void = { _ in }
    var onRecolor: (String) -> Void = { _ in }

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            ColorPicker("", selection: swatchBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 16, height: 16)

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

    private var swatchBinding: Binding<Color> {
        Binding(
            get: { Color(hex: cue.colorHex) ?? .accentColor },
            set: { newColor in
                guard let hex = newColor.hexString, hex != cue.colorHex else { return }
                onRecolor(hex)
            }
        )
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
