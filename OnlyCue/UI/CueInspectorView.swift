import SwiftUI

struct CueInspectorView: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    let cue: Cue?

    @Environment(\.undoManager) var undoManager

    @State private var nameDraft = ""
    @State private var numberDraft = ""
    @State private var numberError: String?
    @State private var fadeDraft = ""
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, number, fade }

    var body: some View {
        VStack(spacing: 8) {
            InspectorClockHeader(engine: engine)
            Group {
                if let cue {
                    fields(for: cue)
                        .id(cue.id)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
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
            VStack(alignment: .leading, spacing: 2) {
                row("Number") {
                    TextField("", text: $numberDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .number)
                        .onSubmit { commitNumber(for: cue) }
                        .onChange(of: numberDraft) { _, _ in numberError = nil }
                        .accessibilityIdentifier("cueInspectorNumber")
                }
                if let numberError {
                    Text(numberError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 60)
                        .accessibilityIdentifier("cueInspectorNumberError")
                }
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
        }
        .onAppear { syncDrafts(from: cue) }
        .onChange(of: cue) { _, new in syncDrafts(from: new) }
        .onChange(of: focused) { old, _ in commitOnFocusLeave(field: old, cue: cue) }
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
        if focused != .number { numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? "" }
        if focused != .fade { fadeDraft = cue.fadeTime.format() }
    }

    private func commitOnFocusLeave(field: Field?, cue: Cue) {
        guard let field else { return }
        switch field {
        case .name: commitName(for: cue)
        case .number: commitNumber(for: cue)
        case .fade: commitFade(for: cue)
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
            let result = CueCommands.setCueNumber(
                cueId: cue.id, to: value, document: document, undoManager: undoManager
            )
            switch result {
            case .ok:
                numberError = nil
                numberDraft = FadeTime.formatNumber(value)
            case .invalidFormat, .duplicate, .outOfRange:
                numberError = CueNumberErrorMessage.text(for: result)
                numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? ""
            }
        case .cleared:
            CueCommands.setCueNumber(cueId: cue.id, to: nil, document: document, undoManager: undoManager)
            numberError = nil
            numberDraft = ""
        case .noChange:
            numberError = nil
            numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? ""
        case .revert(let canonical):
            numberError = CueNumberErrorMessage.invalidFormat
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
}
