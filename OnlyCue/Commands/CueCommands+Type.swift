import Foundation

extension CueCommands {

    /// Changes the `typeID` of every cue in `ids` to `newTypeID` (#752). Pure
    /// retype — only `typeID` changes; time / name / fade and unselected cues
    /// are left untouched. Committed as a single undo step, mirroring
    /// `renumberSelected`. Empty `ids` is a no-op.
    static func setTypeForSelected(
        _ ids: Set<Cue.ID>,
        to newTypeID: CuePointType.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard !ids.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Change Cue Type") { cues in
            cues.map { cue in
                guard ids.contains(cue.id) else { return cue }
                var copy = cue
                copy.typeID = newTypeID
                return copy
            }
        }
    }
}
