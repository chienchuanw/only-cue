import SwiftUI

struct CueRowView: View {

    let cue: Cue
    var resolvedColorHex: String?
    var timeColumnWidth: CGFloat = CueListColumnWidths.timeDefault
    var numberColumnWidth: CGFloat = CueListColumnWidths.numberDefault
    var fadeColumnWidth: CGFloat = CueListColumnWidths.fadeDefault
    var onRename: (String) -> Void = { _ in }
    var onCommitNumber: (Double?) -> CueNumberValidator.Result = { _ in .ok }
    var onCommitFade: (FadeTime) -> Void = { _ in }

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    @State private var isEditingNumber = false
    @State private var numberDraft = ""
    @State private var numberError: String?
    @FocusState private var numberFieldFocused: Bool

    @State private var isEditingFade = false
    @State private var fadeDraft = ""
    @FocusState private var fadeFieldFocused: Bool

    @Environment(\.projectFramerate) private var framerate

    var body: some View {
        HStack(spacing: 0) {
            stripe
                .frame(width: 3)
                .accessibilityIdentifier("cueRowStripe-\(cue.id)")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: CueListLayout.rowHorizontalSpacing) {
                    Text(TimeFormat.smpte(cue.time, rate: framerate))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: timeColumnWidth, alignment: .leading)
                        .accessibilityIdentifier("cueTime-\(cue.id)")

                    numberCell
                        .frame(width: numberColumnWidth, alignment: .leading)
                        .accessibilityIdentifier("cueNumber-\(cue.id)")

                    nameField
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("cueName-\(cue.id)")

                    fadeCell
                        .frame(width: fadeColumnWidth, alignment: .leading)
                        .accessibilityIdentifier("cueRowFade-\(cue.id)")
                }
                if let numberError {
                    Text(numberError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, timeColumnWidth + CueListLayout.rowHorizontalSpacing)
                        .accessibilityIdentifier("cueNumberError-\(cue.id)")
                }
            }
            .padding(.leading, 6)
        }
        .padding(.vertical, 2)
        // Right-click hit-test needs the row's full width, not just text bounds —
        // .contextMenu is applied by the parent `CueListPane` matching the
        // ItemListPane pattern that's proven to work on macOS.
        .contentShape(Rectangle())
        .accessibilityIdentifier("cueRow-\(cue.id)")
    }

    @ViewBuilder
    private var stripe: some View {
        if let hex = resolvedColorHex, let color = Color(hex: hex) {
            Rectangle().fill(color)
        } else {
            Rectangle().fill(Color.clear)
        }
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

    @ViewBuilder
    private var fadeCell: some View {
        if isEditingFade {
            TextField("", text: $fadeDraft)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($fadeFieldFocused)
                .onSubmit { commitFade() }
                .onExitCommand { cancelFadeEdit() }
                .onChange(of: fadeFieldFocused) { _, isFocused in
                    if !isFocused { commitFade() }
                }
                .onAppear { fadeFieldFocused = true }
        } else {
            Text(cue.fadeTime.format())
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginFadeEdit() }
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

    private func beginFadeEdit() {
        fadeDraft = cue.fadeTime.format()
        isEditingFade = true
    }

    private func cancelFadeEdit() {
        isEditingFade = false
    }

    private func commitFade() {
        defer { isEditingFade = false }
        guard let parsed = FadeTime.parse(fadeDraft) else { return }
        guard parsed != cue.fadeTime else { return }
        onCommitFade(parsed)
    }
}
