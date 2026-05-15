import SwiftUI

/// Right-click context menu and modal sheet hosting for `CueListPane`.
/// Pulled out of the main struct so the parent stays readable and
/// SwiftLint's `type_body_length` rule keeps a margin.
/// Identifiable wrapper used by `.sheet(item:)` to drive the Notes /
/// Tempo sheets from a `Cue.ID?` binding. Looks the cue up lazily so the
/// sheet always sees the current model state, never a stale snapshot.
struct CueEditingTarget: Identifiable {
    let cue: Cue
    var id: Cue.ID { cue.id }
}

extension CueListPane {

    /// `.sheet(item:)` bindings for the Notes / Tempo sheets. Looks the cue
    /// up lazily on read so the sheet always sees current model state.
    var notesEditingBinding: Binding<CueEditingTarget?> {
        Binding(
            get: {
                guard let id = notesEditingID,
                      let cue = cues.first(where: { $0.id == id })
                else { return nil }
                return CueEditingTarget(cue: cue)
            },
            set: { newValue in notesEditingID = newValue?.id }
        )
    }

    var tempoEditingBinding: Binding<CueEditingTarget?> {
        Binding(
            get: {
                guard let id = tempoEditingID,
                      let cue = cues.first(where: { $0.id == id })
                else { return nil }
                return CueEditingTarget(cue: cue)
            },
            set: { newValue in tempoEditingID = newValue?.id }
        )
    }

    /// Builds the right-click context menu for a single cue row.
    /// `Change Type ▸` instant-commits via `CueCommands.setType`. `Edit
    /// Notes…` and `Tempo…` set the sheet bindings owned by the parent;
    /// the keyboard shortcuts on those menu items mean they fire even when
    /// the menu isn't open (as long as a row is selected).
    @ViewBuilder
    func cueRowContextMenu(for cue: Cue) -> some View {
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

        Button("Edit Notes…") { notesEditingID = cue.id }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .accessibilityIdentifier("cueRowContextEditNotes")

        Button("Tempo…") { tempoEditingID = cue.id }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .accessibilityIdentifier("cueRowContextTempo")
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
