import Foundation

@MainActor
enum CueCommands {

    // MARK: - Cue mutations (scoped to the active item)

    static func addCueAtPlayhead(
        time: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let defaultType = document.model.cuePointTypes.first else {
            assertionFailure("Project has no CuePointTypes — invariant violated by upstream code")
            return
        }
        appendCue(time: time, typeID: defaultType.id, document: document, undoManager: undoManager)
    }

    /// Explicit-Type variant used by the number-key cue-creation dispatch. The caller
    /// resolves the Type via `ProjectModel.cuePointType(forHotkey:)` and passes its id.
    /// Guards against a typeID that no longer exists in the project — without the guard,
    /// a stale id would produce a cue that resolves to `.accentColor` forever with no
    /// way for the user to tell why the swatch looks wrong.
    static func addCueAtPlayhead(
        time: TimeInterval,
        typeID: CuePointType.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard document.model.cuePointTypes.contains(where: { $0.id == typeID }) else {
            assertionFailure("addCueAtPlayhead called with a typeID that doesn't exist in cuePointTypes")
            return
        }
        appendCue(time: time, typeID: typeID, document: document, undoManager: undoManager)
    }

    private static func appendCue(
        time: TimeInterval,
        typeID: CuePointType.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        let clampedTime = max(time, 0)
        let existingCues = document.model.activeItem?.cues ?? []
        let cue = Cue(
            id: UUID(),
            typeID: typeID,
            cueNumber: CueNumberAssignment.next(forInsertionAt: clampedTime, in: existingCues),
            name: "Cue",
            time: clampedTime,
            notes: "",
            fadeTime: .zero
        )
        mutateCues(document, undoManager: undoManager, actionName: "Add Cue") { cues in
            (cues + [cue]).sorted { $0.time < $1.time }
        }
    }

    static func delete(cueId: Cue.ID, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Delete Cue") { cues in
            cues.filter { $0.id != cueId }
        }
    }

    static func rename(cueId: Cue.ID, to newName: String, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Rename Cue") {
            $0.name = newName
        }
    }

    static func setType(cueId: Cue.ID, to newTypeID: CuePointType.ID, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Type") {
            $0.typeID = newTypeID
        }
    }

    /// Sets or clears a cue's `cueNumber`. Validated against grandMA2 rules
    /// (`CueNumberValidator`); the returned `Result` lets the UI surface an
    /// inline error and revert the field on rejection. Mutating only occurs
    /// on `.ok`.
    @discardableResult
    static func setCueNumber(
        cueId: Cue.ID,
        to newNumber: Double?,
        document: CueListDocument,
        undoManager: UndoManager?
    ) -> CueNumberValidator.Result {
        let cues = document.model.activeItem?.cues ?? []
        let result = CueNumberValidator.validate(candidate: newNumber, for: cueId, in: cues)
        guard result == .ok else { return result }
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Number") {
            $0.cueNumber = newNumber
        }
        return .ok
    }

    static func setFadeTime(cueId: Cue.ID, to newFade: FadeTime, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Fade") {
            $0.fadeTime = newFade
        }
    }

    static func setNotes(cueId: Cue.ID, to newNotes: String, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Notes") {
            $0.notes = newNotes
        }
    }

    /// Drop a new cue at `time` inheriting `typeID`, `name`, `notes`, and `fadeTime`
    /// from the cue with `cueId`. New `id` (UUID) and `cueNumber` (auto-assigned via
    /// `CueNumberAssignment.next` for the new time slot). Silent no-op if `cueId`
    /// doesn't resolve in the active item's cues.
    static func duplicateAtPlayhead(
        cueId: Cue.ID,
        time: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        let existingCues = document.model.activeItem?.cues ?? []
        guard let source = existingCues.first(where: { $0.id == cueId }) else { return }
        let clampedTime = max(time, 0)
        let cue = Cue(
            id: UUID(),
            typeID: source.typeID,
            cueNumber: CueNumberAssignment.next(forInsertionAt: clampedTime, in: existingCues),
            name: source.name,
            time: clampedTime,
            notes: source.notes,
            fadeTime: source.fadeTime
        )
        mutateCues(document, undoManager: undoManager, actionName: "Duplicate Cue") { cues in
            (cues + [cue]).sorted { $0.time < $1.time }
        }
    }

    static func retime(cueId: Cue.ID, to newTime: TimeInterval, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Retime Cue") { cues in
            cues
                .map { cue -> Cue in
                    guard cue.id == cueId else { return cue }
                    var copy = cue
                    copy.time = max(newTime, 0)
                    return copy
                }
                .sorted { $0.time < $1.time }
        }
    }

    /// Shift every cue in `ids` by `delta` seconds (clamped at 0), re-sort, in
    /// one undo step. No-op for an empty set. Used by the multi-select nudge
    /// (`Option+←` / `Option+→`).
    static func nudgeCues(_ ids: Set<Cue.ID>, by delta: TimeInterval, document: CueListDocument, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Nudge Cues") { cues in
            cues
                .map { cue -> Cue in
                    guard ids.contains(cue.id) else { return cue }
                    var copy = cue
                    copy.time = max(cue.time + delta, 0)
                    return copy
                }
                .sorted { $0.time < $1.time }
        }
    }

    /// Move every cue in `ids` to `time` (clamped at 0), re-sort, in one undo
    /// step. No-op for an empty set. Used by the multi-select snap-to-playhead
    /// (`S`) — note that snapping several cues to the same point stacks them.
    static func snapCues(_ ids: Set<Cue.ID>, to time: TimeInterval, document: CueListDocument, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Snap Cues") { cues in
            cues
                .map { cue -> Cue in
                    guard ids.contains(cue.id) else { return cue }
                    var copy = cue
                    copy.time = max(time, 0)
                    return copy
                }
                .sorted { $0.time < $1.time }
        }
    }

    // MARK: - Internals

    private static func updateCue(
        cueId: Cue.ID,
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        update: (inout Cue) -> Void
    ) {
        mutateCues(document, undoManager: undoManager, actionName: actionName) { cues in
            cues.map { cue in
                guard cue.id == cueId else { return cue }
                var copy = cue
                update(&copy)
                return copy
            }
        }
    }

    static func mutateCues(
        _ document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        _ change: ([Cue]) -> [Cue]
    ) {
        guard let index = document.model.activeItemIndex else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let before = document.model.items[index].cues
        document.model.items[index].cues = change(before)
        let itemID = document.model.items[index].id
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreCues(itemID: itemID, to: before, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private static func restoreCues(
        itemID: MediaItem.ID,
        to oldCues: [Cue],
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let current = document.model.items[index].cues
        document.model.items[index].cues = oldCues
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreCues(itemID: itemID, to: current, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

}
