import SwiftUI

/// View modifier that listens for `.exportMA2PluginRequested` (#683/#688),
/// resolves the target media item (notification object = `MediaItem.ID`, nil =
/// active item), and presents `MA2PluginExportSheet`. Saving the target back to
/// the document goes through `CueCommands.setMA2PushTarget` — never a direct
/// model write. The pre-flight / save-panel / write-error handling lives in the
/// sheet.
struct MA2PluginExportPresenter: ViewModifier {

    let document: CueListDocument
    let undoManager: UndoManager?

    @State private var presentedItem: MediaItem?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportMA2PluginRequested)) { note in
                let requestedID = note.object as? MediaItem.ID
                let itemID = requestedID ?? document.model.activeItemID
                presentedItem = document.model.items.first { $0.id == itemID }
            }
            .sheet(item: $presentedItem) { item in
                MA2PluginExportSheet(
                    item: item,
                    cuePointTypes: document.model.cuePointTypes,
                    framerate: document.model.timecodeSettings.framerate,
                    onSaveTarget: { target in
                        CueCommands.setMA2PushTarget(
                            target,
                            itemID: item.id,
                            document: document,
                            undoManager: undoManager
                        )
                    },
                    onDismiss: { presentedItem = nil }
                )
            }
    }
}

extension View {
    func ma2PluginExport(document: CueListDocument, undoManager: UndoManager?) -> some View {
        modifier(MA2PluginExportPresenter(document: document, undoManager: undoManager))
    }
}
