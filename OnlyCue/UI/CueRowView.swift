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
    /// When true (Show mode) the row's editable fields are disabled.
    var isReadOnly: Bool = false

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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CueListLayout.rowHorizontalSpacing) {
                Text(TimeFormat.smpte(cue.time, rate: framerate))
                    .font(DS.Text.monoSmall)
                    .foregroundStyle(DS.Color.textSecondary)
                    // One line: the SMPTE string must never wrap to two
                    // rows when the column compresses (Figma 318:1228).
                    .lineLimit(1)
                    .cueColumnFrame(width: timeColumnWidth, range: CueListColumnWidths.timeRange)
                    .accessibilityIdentifier("cueTime-\(cue.id)")

                numberCell
                    .cueColumnFrame(width: numberColumnWidth, range: CueListColumnWidths.numberRange)
                    .accessibilityIdentifier("cueNumber-\(cue.id)")

                nameField
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("cueName-\(cue.id)")

                fadeCell
                    .cueColumnFrame(width: fadeColumnWidth, range: CueListColumnWidths.fadeRange)
                    .accessibilityIdentifier("cueRowFade-\(cue.id)")
            }
            if let numberError {
                Text(numberError)
                    .font(.caption2)
                    .foregroundStyle(.red) // semantic: error
                    .padding(.leading, timeColumnWidth + CueListLayout.rowHorizontalSpacing)
                    .accessibilityIdentifier("cueNumberError-\(cue.id)")
            }
        }
        // Match the header's gutter/edge padding so the columns line up exactly.
        .padding(.leading, CueListLayout.rowLeadingGutter)
        .padding(.trailing, CueListLayout.rowHorizontalPadding)
        .padding(.vertical, DS.Space.xs / 2)
        // Cue-type colour as a 5pt full-height left stripe (Figma 318:1326
        // TypeBar) — replaces the leading dot; the selected-row tint is applied
        // by the parent list's row background.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(stripeColor)
                .frame(width: CueListLayout.typeStripeWidth)
                .accessibilityIdentifier("cueRowSwatch-\(cue.id)")
        }
        // Right-click hit-test needs the row's full width, not just text bounds —
        // .contextMenu is applied by the parent `CueListPane` matching the
        // ItemListPane pattern that's proven to work on macOS.
        .contentShape(Rectangle())
        .disabled(isReadOnly)
        .accessibilityIdentifier("cueRow-\(cue.id)")
    }

    /// The cue-type colour for the leading stripe, falling back to the neutral
    /// border when the cue has no resolved colour.
    private var stripeColor: Color {
        resolvedColorHex.flatMap { Color(hex: $0) } ?? DS.Color.border
    }

    @ViewBuilder
    private var numberCell: some View {
        if isEditingNumber {
            TextField("", text: $numberDraft)
                .textFieldStyle(.plain)
                .font(DS.Text.monoSmall)
                .focused($numberFieldFocused)
                .onSubmit { commitNumber() }
                .onExitCommand { cancelNumberEdit() }
                .onChange(of: numberFieldFocused) { _, isFocused in
                    if !isFocused { commitNumber() }
                }
                .onChange(of: numberDraft) { _, _ in numberError = nil }
                .onAppear { numberFieldFocused = true }
                .focusedValue(\.editingCueField, true)
        } else {
            Text(cue.cueNumber.map(FadeTime.formatNumber) ?? "")
                .font(DS.Text.monoSmall)
                .foregroundStyle(cue.cueNumber == nil ? DS.Color.textTertiary : DS.Color.textPrimary)
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
                .focusedValue(\.editingCueField, true)
        } else {
            Text(cue.name.isEmpty ? "Untitled" : cue.name)
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textPrimary)
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
                .font(DS.Text.monoSmall)
                .focused($fadeFieldFocused)
                .onSubmit { commitFade() }
                .onExitCommand { cancelFadeEdit() }
                .onChange(of: fadeFieldFocused) { _, isFocused in
                    if !isFocused { commitFade() }
                }
                .onAppear { fadeFieldFocused = true }
                .focusedValue(\.editingCueField, true)
        } else {
            // Glance-only display carries the `" s"` unit (Figma 318:1228); the
            // edit draft still uses `format()` so it round-trips through parse.
            Text(cue.fadeTime.columnDisplay)
                .font(DS.Text.monoSmall)
                .foregroundStyle(DS.Color.textSecondary)
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
