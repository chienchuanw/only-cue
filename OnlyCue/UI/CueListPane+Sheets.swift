import SwiftUI

/// Right-click context menu and modal sheet hosting for `CueListPane`.
/// Pulled out of the main struct so the parent stays readable and
/// SwiftLint's `type_body_length` rule keeps a margin.
/// Tagged identifier for the single `.sheet(item:)` modifier that hosts
/// both the Notes and Tempo cue editors. SwiftUI only honors one
/// `.sheet` modifier per view; stacking two `.sheet(item:)` modifiers
/// silently drops state changes for both, which is what masked the
/// click-doesn't-open-sheet bug behind the `.contextMenu` issue.
enum CueSheetKind: Identifiable, Equatable {
    case notes(Cue.ID)
    case tempo(Cue.ID)
    /// Resequence the current multi-selection's cue numbers (#535). Carries no
    /// single cue id — it operates on `CueListPane.selection`.
    case renumber

    var id: String {
        switch self {
        case .notes(let id): return "notes-\(id.uuidString)"
        case .tempo(let id): return "tempo-\(id.uuidString)"
        case .renumber: return "renumber"
        }
    }

    /// The target cue for the single-cue sheets; nil for `.renumber`, which
    /// works on the whole selection.
    var cueID: Cue.ID? {
        switch self {
        case .notes(let id), .tempo(let id): return id
        case .renumber: return nil
        }
    }
}

extension CueListPane {

    /// Resolves the active `CueSheetKind` into the corresponding modal
    /// sheet view. Returns an empty placeholder if the cue has been
    /// deleted between menu click and sheet presentation.
    @ViewBuilder
    func cueSheetContent(for sheet: CueSheetKind) -> some View {
        if case .renumber = sheet {
            renumberSheet()
        } else if let cueID = sheet.cueID, let cue = cues.first(where: { $0.id == cueID }) {
            switch sheet {
            case .renumber:
                EmptyView() // handled above
            case .notes:
                CueNotesSheet(
                    cueLabel: cueSheetLabel(for: cue),
                    initialNotes: cue.notes,
                    onSave: { newNotes in
                        CueCommands.setNotes(
                            cueId: cue.id,
                            to: newNotes,
                            document: document,
                            undoManager: undoManager
                        )
                        activeCueSheet = nil
                    },
                    onCancel: { activeCueSheet = nil }
                )
            case .tempo:
                CueTempoSheet(
                    cueLabel: cueSheetLabel(for: cue),
                    initialBPM: cue.bpm,
                    initialBeatsPerBar: cue.beatsPerBar,
                    onDetect: { beats in
                        await runTempoDetect(for: cue, beatsPerBar: beats)
                    },
                    onSave: { bpm, beats in
                        if let itemID = itemID(owning: cue.id) {
                            CueCommands.setCueTempo(
                                cueID: cue.id,
                                bpm: bpm,
                                beatsPerBar: beats,
                                item: itemID,
                                document: document,
                                undoManager: undoManager
                            )
                        }
                        activeCueSheet = nil
                    },
                    onCancel: { activeCueSheet = nil }
                )
            }
        } else {
            Color.clear.onAppear { activeCueSheet = nil }
        }
    }

    /// The "Renumber Selected…" sheet (#535), extracted so `cueSheetContent`
    /// stays within SwiftLint's `function_body_length`.
    @ViewBuilder
    func renumberSheet() -> some View {
        RenumberCuesSheet(
            cueCount: selection.count,
            onRenumber: { start, interval in
                CueCommands.renumberSelected(
                    selection,
                    start: start,
                    interval: interval,
                    document: document,
                    undoManager: undoManager
                )
                activeCueSheet = nil
            },
            onCancel: { activeCueSheet = nil }
        )
    }

    /// The per-row right-click menu — empty (no menu) when the list is
    /// read-only (Show mode). Lives here (not in the main struct) so
    /// `CueListPane.swift` stays under SwiftLint's `file_length`.
    @ViewBuilder
    func cueContextMenu(for cue: Cue) -> some View {
        if !isReadOnly {
            Button("Edit Notes…") { activeCueSheet = .notes(cue.id) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .accessibilityIdentifier("cueRowContextEditNotes")
            Button("Tempo…") { activeCueSheet = .tempo(cue.id) }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .accessibilityIdentifier("cueRowContextTempo")
            if selection.count >= 2 {
                Button("Renumber Selected…") { activeCueSheet = .renumber }
                    .accessibilityIdentifier("cueRowContextRenumberSelected")
            }
            Menu("Change Type") {
                ForEach(document.model.cuePointTypes) { type in
                    Button {
                        guard type.id != cue.typeID else { return }
                        CueCommands.setType(
                            cueId: cue.id,
                            to: type.id,
                            document: document,
                            undoManager: undoManager
                        )
                    } label: {
                        Label {
                            Text(type.name)
                        } icon: {
                            if type.id == cue.typeID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("cueRowContextChangeType-\(type.id)")
                }
            }
            .accessibilityIdentifier("cueRowContextChangeType")
        }
    }

    /// Display label for sheet titles — "Cue 12 · Blackout" when numbered,
    /// "Blackout" otherwise. Untitled cues degrade to "Untitled".
    func cueSheetLabel(for cue: Cue) -> String {
        let name = cue.name.isEmpty ? "Untitled" : cue.name
        if let number = cue.cueNumber {
            return "Cue \(FadeTime.formatNumber(number)) · \(name)"
        }
        return name
    }

    /// Looks up the MediaItem.ID that owns `cueID`. Returns nil if the cue
    /// has been deleted between the menu click and the sheet's onSave —
    /// guarded against because both happen asynchronously.
    func itemID(owning cueID: Cue.ID) -> MediaItem.ID? {
        document.model.items.first(where: { $0.cues.contains(where: { $0.id == cueID }) })?.id
    }

    /// Runs the same audio-window selection logic the inspector used to,
    /// and routes through `CueTempoDetect`. Returns the formatted result
    /// the sheet uses to populate its BPM draft — or nil when no usable
    /// outcome (no audio, detect failure, no estimate).
    func runTempoDetect(
        for cue: Cue,
        beatsPerBar: Int
    ) async -> CueTempoSheet.DetectResult? {
        guard let item = document.model.items.first(where: { $0.cues.contains(where: { $0.id == cue.id }) }) else {
            return nil
        }
        let cueTime = cue.time
        let nextBPMCueTime = item.cues
            .filter { $0.id != cue.id && $0.time > cueTime && $0.bpm != nil }
            .map(\.time)
            .min()
        let detectEnd = min(nextBPMCueTime ?? item.media.duration, cueTime + 30)
        let outcome = await CueTempoDetect.detect(
            bookmark: item.media.bookmarkData,
            range: cueTime < detectEnd ? cueTime...detectEnd : nil,
            beatsPerBar: beatsPerBar
        )
        switch outcome {
        case .found(let estimate):
            let msg: String? = estimate.confidence < 0.4
                ? "Low confidence (\(Int((estimate.confidence * 100).rounded()))%)"
                : nil
            return (bpm: estimate.bpm, message: msg)
        case .notDetected, .noAudio, .failed:
            return nil
        }
    }
}
