import SwiftUI

struct CueRowView: View {

    static let palette: [(name: String, hex: String)] = [
        ("Red", "#FF6B6B"),
        ("Orange", "#FFA94D"),
        ("Yellow", "#FFD93D"),
        ("Green", "#6BCB77"),
        ("Teal", "#4ECDC4"),
        ("Blue", "#4D96FF"),
        ("Purple", "#9D7EE0"),
        ("Pink", "#FF6FB5")
    ]

    let index: Int
    let cue: Cue
    var resolvedColorHex: String?
    var onRename: (String) -> Void = { _ in }
    var onRecolor: (String) -> Void = { _ in }

    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var showColorPopover = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            colorMenu

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

    private var colorMenu: some View {
        Button {
            showColorPopover.toggle()
        } label: {
            Circle()
                .fill(swatchColor)
                .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 0.5))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.palette, id: \.hex) { entry in
                    Button {
                        if entry.hex != resolvedColorHex { onRecolor(entry.hex) }
                        showColorPopover = false
                    } label: {
                        HStack(spacing: 8) {
                            CueColorSwatch(hex: entry.hex)
                            Text(entry.name)
                            Spacer(minLength: 12)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                }
            }
            .padding(6)
            .frame(minWidth: 140)
        }
        .accessibilityIdentifier("cueColorButton-\(index)")
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

    private var swatchColor: Color {
        guard let hex = resolvedColorHex else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
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
