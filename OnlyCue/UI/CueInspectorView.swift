import SwiftUI

struct CueInspectorView: View {

    @ObservedObject var document: CueListDocument
    let cue: Cue?

    @Environment(\.undoManager) private var undoManager

    @State private var nameDraft = ""
    @State private var numberDraft = ""
    @State private var fadeDraft = ""
    @State private var notesDraft = ""
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, number, fade, notes }

    var body: some View {
        Group {
            if let cue {
                fields(for: cue)
                    .id(cue.id)
            } else {
                emptyState
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("cueInspector")
    }

    private var emptyState: some View {
        Text("Select a cue")
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("cueInspectorEmptyState")
    }

    @ViewBuilder
    private func fields(for cue: Cue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            typePicker(for: cue)
            row("Number") {
                TextField("", text: $numberDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .number)
                    .onSubmit { commitNumber(for: cue) }
                    .accessibilityIdentifier("cueInspectorNumber")
            }
            row("Name") {
                TextField("", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .name)
                    .onSubmit { commitName(for: cue) }
                    .accessibilityIdentifier("cueInspectorName")
            }
            row("Fade") {
                TextField("", text: $fadeDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .fade)
                    .onSubmit { commitFade(for: cue) }
                    .accessibilityIdentifier("cueInspectorFade")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notesDraft)
                    .focused($focused, equals: .notes)
                    .frame(minHeight: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                    .accessibilityIdentifier("cueInspectorNotes")
            }
        }
        .onAppear { syncDrafts(from: cue) }
        .onChange(of: cue) { _, new in syncDrafts(from: new) }
        .onChange(of: focused) { old, _ in commitOnFocusLeave(field: old, cue: cue) }
    }

    private func typePicker(for cue: Cue) -> some View {
        let types = document.model.cuePointTypes
        let selection = Binding(
            get: { cue.typeID },
            set: { newID in
                guard newID != cue.typeID else { return }
                CueCommands.setType(cueId: cue.id, to: newID, document: document, undoManager: undoManager)
            }
        )
        return row("Type") {
            Picker("", selection: selection) {
                ForEach(types) { type in
                    HStack(spacing: 6) {
                        CueColorSwatch(hex: type.colorHex, diameter: 10)
                        Text(type.name)
                    }
                    .tag(type.id)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("cueInspectorType")
        }
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            content()
        }
    }

    /// Sync drafts from the cue, but skip the field the user is currently editing —
    /// otherwise an external mutation (marker drag retime, undo) clobbers in-progress input.
    private func syncDrafts(from cue: Cue) {
        if focused != .name { nameDraft = cue.name }
        if focused != .number { numberDraft = FadeTime.formatNumber(cue.cueNumber) }
        if focused != .fade { fadeDraft = cue.fadeTime.format() }
        if focused != .notes { notesDraft = cue.notes }
    }

    private func commitOnFocusLeave(field: Field?, cue: Cue) {
        guard let field else { return }
        switch field {
        case .name: commitName(for: cue)
        case .number: commitNumber(for: cue)
        case .fade: commitFade(for: cue)
        case .notes: commitNotes(for: cue)
        }
    }

    private func commitName(for cue: Cue) {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != cue.name else {
            nameDraft = cue.name
            return
        }
        CueCommands.rename(cueId: cue.id, to: trimmed, document: document, undoManager: undoManager)
    }

    private func commitNumber(for cue: Cue) {
        switch CueInspectorCommit.commitCueNumber(draft: numberDraft, current: cue.cueNumber) {
        case .parsed(let value):
            CueCommands.setCueNumber(cueId: cue.id, to: value, document: document, undoManager: undoManager)
            numberDraft = FadeTime.formatNumber(value)
        case .noChange:
            numberDraft = FadeTime.formatNumber(cue.cueNumber)
        case .revert(let canonical):
            numberDraft = canonical
        }
    }

    private func commitFade(for cue: Cue) {
        switch CueInspectorCommit.commitFadeTime(draft: fadeDraft, current: cue.fadeTime) {
        case .parsed(let fade):
            CueCommands.setFadeTime(cueId: cue.id, to: fade, document: document, undoManager: undoManager)
            fadeDraft = fade.format()
        case .noChange:
            fadeDraft = cue.fadeTime.format()
        case .revert(let canonical):
            fadeDraft = canonical
        }
    }

    private func commitNotes(for cue: Cue) {
        guard notesDraft != cue.notes else { return }
        CueCommands.setNotes(cueId: cue.id, to: notesDraft, document: document, undoManager: undoManager)
    }
}
