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
    @State private var notesDraft = ""
    @State var bpmDraft = ""
    @State var beatsPerBarDraft = ""
    @State var detectingCueID: Cue.ID?
    @State var detectMessage: String?
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, number, fade, notes, bpm, beatsPerBar }

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
            typePicker(for: cue)
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
            tempoSection(for: cue)
        }
        .onAppear { syncDrafts(from: cue) }
        .onChange(of: cue) { _, new in syncDrafts(from: new) }
        .onChange(of: focused) { old, _ in commitOnFocusLeave(field: old, cue: cue) }
    }

    @ViewBuilder
    private func tempoSection(for cue: Cue) -> some View {
        row("BPM") {
            HStack(spacing: 6) {
                TextField("inherited", text: $bpmDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .bpm)
                    .onSubmit { commitBPM(for: cue) }
                    .accessibilityIdentifier("cueInspectorBPM")
                TextField("4", text: $beatsPerBarDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .beatsPerBar)
                    .onSubmit { commitBeatsPerBar(for: cue) }
                    .frame(width: 40)
                    .accessibilityIdentifier("cueInspectorBeatsPerBar")
                Text("/ bar").font(.caption).foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 8) {
            Button("Detect") { detectTempo(for: cue) }
                .accessibilityIdentifier("cueInspectorDetectTempo")
                .disabled(detectingCueID == cue.id)
            Button("Clear") { clearTempo(for: cue) }
                .accessibilityIdentifier("cueInspectorClearTempo")
                .disabled(cue.bpm == nil && cue.beatsPerBar == nil)
            if let detectMessage {
                Text(detectMessage).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.leading, 60)
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
        if focused != .number { numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? "" }
        if focused != .fade { fadeDraft = cue.fadeTime.format() }
        if focused != .notes { notesDraft = cue.notes }
        if focused != .bpm { bpmDraft = cue.bpm.map { String(Int($0.rounded())) } ?? "" }
        if focused != .beatsPerBar { beatsPerBarDraft = cue.beatsPerBar.map(String.init) ?? "" }
    }

    private func commitOnFocusLeave(field: Field?, cue: Cue) {
        guard let field else { return }
        switch field {
        case .name: commitName(for: cue)
        case .number: commitNumber(for: cue)
        case .fade: commitFade(for: cue)
        case .notes: commitNotes(for: cue)
        case .bpm: commitBPM(for: cue)
        case .beatsPerBar: commitBeatsPerBar(for: cue)
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

    private func commitNotes(for cue: Cue) {
        guard notesDraft != cue.notes else { return }
        CueCommands.setNotes(cueId: cue.id, to: notesDraft, document: document, undoManager: undoManager)
    }

}
