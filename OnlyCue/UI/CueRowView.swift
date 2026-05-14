import SwiftUI

struct CueRowView: View {

    let index: Int
    let cue: Cue
    var resolvedColorHex: String?
    var onRename: (String) -> Void = { _ in }
    var onCommitNumber: (Double?) -> CueNumberValidator.Result = { _ in .ok }

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    @State private var isEditingNumber = false
    @State private var numberDraft = ""
    @State private var numberError: String?
    @FocusState private var numberFieldFocused: Bool

    @AppStorage("showBPMColumn") private var showBPMColumn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)

                numberCell
                    .frame(width: 56, alignment: .leading)
                    .accessibilityIdentifier("cueNumber-\(index)")

                CueColorSwatch(hex: resolvedColorHex, diameter: 14)
                    .accessibilityIdentifier("cueColorSwatch-\(index)")

                nameField
                    .accessibilityIdentifier("cueName-\(index)")

                Spacer(minLength: 8)

                if showBPMColumn {
                    Text(cue.bpm.map { String(Int($0.rounded())) } ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(cue.bpm == nil ? .tertiary : .secondary)
                        .frame(width: 36, alignment: .trailing)
                        .accessibilityIdentifier("cueBPM-\(index)")
                }

                Text(TimeFormat.hms(cue.time))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let numberError {
                Text(numberError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 36)
                    .accessibilityIdentifier("cueNumberError-\(index)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("cueRow-\(index)")
    }

    @ViewBuilder
    private var numberCell: some View {
        if isEditingNumber {
            TextField("", text: $numberDraft)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($numberFieldFocused)
                .onSubmit { commitNumber() }
                .onExitCommand { cancelNumberEdit() }
                .onChange(of: numberFieldFocused) { _, isFocused in
                    if !isFocused { commitNumber() }
                }
                .onChange(of: numberDraft) { _, _ in numberError = nil }
                .onAppear { numberFieldFocused = true }
        } else {
            Text(cue.cueNumber.map(FadeTime.formatNumber) ?? "")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(cue.cueNumber == nil ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginNumberEdit() }
        }
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

    private func beginNumberEdit() {
        numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? ""
        numberError = nil
        isEditingNumber = true
    }

    private func cancelNumberEdit() {
        numberError = nil
        isEditingNumber = false
    }

    private func commitNumber() {
        defer { isEditingNumber = false }
        switch CueInspectorCommit.commitCueNumber(draft: numberDraft, current: cue.cueNumber) {
        case .parsed(let value):
            let result = onCommitNumber(value)
            if result != .ok {
                numberError = CueNumberErrorMessage.text(for: result)
            }
        case .cleared:
            _ = onCommitNumber(nil)
        case .noChange:
            break
        case .revert:
            numberError = CueNumberErrorMessage.invalidFormat
        }
    }
}
