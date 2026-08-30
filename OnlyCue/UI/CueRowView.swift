import AppKit
import SwiftUI

struct CueRowView: View {

    let cue: Cue
    var resolvedColorHex: String?
    var numberColumnWidth: CGFloat = CueListColumnWidths.numberDefault
    var infoColumnWidth: CGFloat = CueListColumnWidths.infoDefault
    var onRename: (String) -> Void = { _ in }
    var onCommitNumber: (Double?) -> CueNumberValidator.Result = { _ in .ok }
    var onCommitNotes: (String) -> Void = { _ in }
    /// Make this row the selection. Fires before an edit begins, so the cue
    /// being typed into is also the one Delete and Renumber act on (#786).
    var onSelect: () -> Void = {}
    /// Toggle this row's membership of the selection — the modifier-click path.
    var onExtendSelection: () -> Void = {}
    /// Move the playhead to this cue's time. The colour stripe only: editing
    /// text must never seek.
    var onSeek: () -> Void = {}
    /// When true (Show mode) the row's editable fields are disabled.
    var isReadOnly: Bool = false

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    @State private var isEditingNumber = false
    @State private var numberDraft = ""
    @State private var numberError: String?
    @FocusState private var numberFieldFocused: Bool

    @State private var isEditingInfo = false
    @State private var infoDraft = ""
    @FocusState private var infoFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CueListLayout.rowHorizontalSpacing) {
                numberCell
                    .cueColumnFrame(width: numberColumnWidth, range: CueListColumnWidths.numberRange)
                    .accessibilityIdentifier("cueNumber-\(cue.id)")

                nameField
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("cueName-\(cue.id)")

                infoCell
                    .cueColumnFrame(width: infoColumnWidth, range: CueListColumnWidths.infoRange)
                    .accessibilityIdentifier("cueInfo-\(cue.id)")
            }
            // Scoped to the columns rather than the whole row (#786): the
            // stripe is an overlay on the enclosing `VStack`, so it stays live
            // in Show mode and remains the way to move the playhead.
            .disabled(isReadOnly)
            if let numberError {
                Text(numberError)
                    .font(.caption2)
                    .foregroundStyle(.red) // semantic: error
                    .padding(.leading, numberColumnWidth + CueListLayout.rowHorizontalSpacing)
                    .accessibilityIdentifier("cueNumberError-\(cue.id)")
            }
        }
        // Match the header's gutter/edge padding so the columns line up exactly.
        .padding(.leading, CueListLayout.rowLeadingGutter)
        .padding(.trailing, CueListLayout.rowHorizontalPadding)
        .padding(.vertical, DS.Space.xs / 2)
        .overlay(alignment: .leading) { typeStripe }
        // Right-click hit-test needs the row's full width, not just text bounds —
        // .contextMenu is applied by the parent `CueListPane` matching the
        // ItemListPane pattern that's proven to work on macOS.
        .contentShape(Rectangle())
        .accessibilityIdentifier("cueRow-\(cue.id)")
    }

    /// The cue-type colour for the leading stripe, falling back to the neutral
    /// border when the cue has no resolved colour.
    private var stripeColor: Color {
        resolvedColorHex.flatMap { Color(hex: $0) } ?? DS.Color.border
    }

    /// Cue-type colour as a 5pt full-height left stripe (Figma 318:1326
    /// TypeBar), and also the row's handle: with a plain click inside any
    /// column now meaning "type here", this is the only mouse path left to the
    /// selection and the playhead (#786).
    ///
    /// The drawn width stays 5pt; only the hit area widens, and it stops at the
    /// gutter so it steals no clicks from the `#` column. It stays live in Show
    /// mode — the columns are locked there, so without it the cue list would
    /// have no way to move the playhead at all.
    private var typeStripe: some View {
        Rectangle()
            .fill(stripeColor)
            .frame(width: CueListLayout.typeStripeWidth)
            .frame(width: CueListLayout.typeStripeHitWidth, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { handleTap(on: .stripe) }
            // `.set()` rather than the push/pop pair `WaveformZoomMagnifier`
            // uses (the `ColumnResizeHandle` idiom): list rows recycle out from
            // under a hovering pointer, and there is no cursor stack to leak.
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            .help("Go to cue")
            // A bare `Rectangle` is not in the AX tree at all, so the handle
            // has to be declared as an element. No identifier of its own: the
            // row's `cueRow-<id>` propagates down and overrides any child's,
            // which is exactly how the existing cue-list UI tests find rows —
            // so the label is what identifies the stripe.
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Go to cue")
            // `.onTapGesture` registers no accessibility activation, so without
            // this the element announces as a button that VoiceOver cannot
            // press — and since selecting a cue no longer seeks, the stripe is
            // the cue list's only path to the playhead.
            .accessibilityAction { handleTap(on: .stripe) }
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
                .onTapGesture { handleTap(on: .field, beginEditing: beginNumberEdit) }
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
                .onChange(of: nameFieldFocused) { _, isFocused in
                    if !isFocused { commitRename() }
                }
                .onAppear { nameFieldFocused = true }
                .focusedValue(\.editingCueField, true)
        } else {
            // Empty name renders blank (#661) — no "Untitled". The column frame
            // + contentShape keep the whole cell clickable even when blank, so
            // the user can still start typing a name.
            Text(cue.name)
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleTap(on: .field, beginEditing: beginRename) }
        }
    }

    /// The Info cell surfaces the cue's `notes` inline (#661); the right-click
    /// Notes sheet remains for longer text.
    @ViewBuilder
    private var infoCell: some View {
        if isEditingInfo {
            TextField("Info", text: $infoDraft)
                .textFieldStyle(.plain)
                .font(DS.Text.small)
                .focused($infoFieldFocused)
                .onSubmit { commitInfo() }
                .onExitCommand { cancelInfoEdit() }
                .onChange(of: infoFieldFocused) { _, isFocused in
                    if !isFocused { commitInfo() }
                }
                .onAppear { infoFieldFocused = true }
                .focusedValue(\.editingCueField, true)
        } else {
            Text(cue.notes)
                .font(DS.Text.small)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleTap(on: .field, beginEditing: beginInfoEdit) }
        }
    }

    // MARK: - Tap routing

    /// A plain click in a column types there, a plain click on the stripe
    /// seeks, and ⌘/⇧ anywhere means "I am selecting, not doing either".
    private func handleTap(on target: CueRowTapTarget, beginEditing: () -> Void = {}) {
        switch CueRowTap.intent(target: target, isExtending: Self.isExtending, isReadOnly: isReadOnly) {
        case .beginEdit:
            onSelect()
            beginEditing()
        case .extendSelection:
            onExtendSelection()
        case .selectAndSeek:
            onSelect()
            onSeek()
        case .ignored:
            break
        }
    }

    /// Read exactly the way `CueMarkersOverlay.handleTap` reads it, so the
    /// timeline and the cue list agree on what a modifier-click means.
    private static var isExtending: Bool {
        let modifiers = NSEvent.modifierFlags
        return modifiers.contains(.command) || modifiers.contains(.shift)
    }

    // MARK: - Commit / cancel
    //
    // Return commits twice in theory — `onSubmit` fires, lowering the flag tears
    // the `TextField` down, and that drops focus into the focus-loss commit —
    // but not in practice: SwiftUI tears the `.onChange` down with the field, and
    // the second call would in any case see its own write and short-circuit in
    // `CueInspectorCommit`. Measured, not assumed
    // (`test_renameThenUndo_revertsInASingleUndo` is red if a rename ever costs
    // two undo entries), so no re-entry guard is carried here.
    //
    // `cancel*` restores its draft to the model's current value, so the field
    // shows the right text if it is ever re-entered.

    private func beginRename() {
        draftName = cue.name
        isEditingName = true
    }

    private func commitRename() {
        isEditingName = false
        if let newName = CueInspectorCommit.commitCueName(draft: draftName, current: cue.name) {
            onRename(newName)
        }
    }

    private func cancelRename() {
        draftName = cue.name
        isEditingName = false
    }

    private func resetNumberDraft() {
        numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? ""
        numberError = nil
    }

    private func beginNumberEdit() {
        resetNumberDraft()
        isEditingNumber = true
    }

    private func cancelNumberEdit() {
        resetNumberDraft()
        isEditingNumber = false
    }

    private func commitNumber() {
        isEditingNumber = false
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

    private func beginInfoEdit() {
        infoDraft = cue.notes
        isEditingInfo = true
    }

    private func cancelInfoEdit() {
        infoDraft = cue.notes
        isEditingInfo = false
    }

    private func commitInfo() {
        isEditingInfo = false
        guard infoDraft != cue.notes else { return }
        onCommitNotes(infoDraft)
    }
}
