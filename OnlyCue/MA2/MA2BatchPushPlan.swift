import Foundation

/// Turns the batch sheet's selected songs into the per-song command lists the
/// `MA2BatchPushRunner` executes (#765). For each selection it first persists the auto-fill
/// numbers (#763) through the command seam so the console and the app agree, then builds the
/// telnet command list from the song's type-filtered, now-numbered cues and its target
/// (executor optional, #764). Songs whose cues cannot produce commands (e.g. all filtered
/// out) are skipped.
@MainActor
enum MA2BatchPushPlan {

    struct Selection {
        let itemID: MediaItem.ID
        let target: MA2PushTarget
    }

    static func build(
        _ selections: [Selection],
        document: CueListDocument,
        undoManager: UndoManager?,
        framerate: SMPTEFramerate
    ) -> [MA2BatchPushRunner.SongCommands] {
        // Persist auto-fill for every selected song first (one undo group for the batch).
        undoManager?.beginUndoGrouping()
        for selection in selections {
            CueCommands.autoFillCueNumbers(itemID: selection.itemID, document: document, undoManager: undoManager)
        }
        undoManager?.endUndoGrouping()

        return selections.compactMap { selection in
            guard let item = document.model.items.first(where: { $0.id == selection.itemID }) else { return nil }
            let cues = CueExportFilter.cues(item.cues, onlyTypeIDs: selection.target.includedTypeIDs)
            guard !cues.isEmpty else { return nil }
            let name = MA2PushRequestBuilder.resolvedSequenceName(item: item, target: selection.target)
            let commands = MA2CommandPlanner.commands(
                cues: cues,
                target: selection.target,
                sequenceName: name,
                startTimecodeFrames: item.startTimecodeFrames,
                framerate: framerate
            )
            return MA2BatchPushRunner.SongCommands(itemID: item.id, name: name, commands: commands)
        }
    }
}
