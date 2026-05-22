import Foundation

@MainActor
extension CueCommands {

    /// How an imported cue list combines with the active item's existing cues.
    enum CueImportMode {
        case replace
        case add
    }

    /// Apply a decoded `.occues` payload to the document's active media item.
    /// Reconciles the payload's types additively into the catalog, remaps the
    /// imported cues onto the new types, and writes both in a single undo group
    /// ("Import Cue List"). No-op when there is no active item.
    static func importCueList(
        _ export: CueListExport,
        mode: CueImportMode,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let activeID = document.model.activeItemID,
              let itemIndex = document.model.items.firstIndex(where: { $0.id == activeID })
        else { return }

        let reconciliation = CueListTransfer.reconcileTypes(
            export.cuePointTypes,
            existing: document.model.cuePointTypes
        )
        let importedCues = CueListTransfer.reconcileCues(
            export.cues,
            idMap: reconciliation.idMap
        )

        mutateProject(document, undoManager: undoManager, actionName: "Import Cue List") { model in
            model.cuePointTypes.append(contentsOf: reconciliation.typesToAdd)
            switch mode {
            case .replace:
                model.items[itemIndex].cues = importedCues
            case .add:
                model.items[itemIndex].cues.append(contentsOf: importedCues)
            }
        }
    }
}
