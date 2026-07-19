import SwiftUI

/// View modifier that listens for `.sendToMA2Requested` (#683), resolves the
/// target media item (notification object = `MediaItem.ID`, nil = active
/// item), and presents `MA2PushSheet`. Saving the target back to the document
/// goes through `CueCommands.setMA2PushTarget` — never a direct model write.
struct MA2PushSheetPresenter: ViewModifier {

    let document: CueListDocument
    let undoManager: UndoManager?

    @State private var presentedItem: MediaItem?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .sendToMA2Requested)) { note in
                let requestedID = note.object as? MediaItem.ID
                let itemID = requestedID ?? document.model.activeItemID
                presentedItem = document.model.items.first { $0.id == itemID }
            }
            .sheet(item: $presentedItem) { item in
                MA2PushSheet(
                    item: item,
                    cuePointTypes: document.model.cuePointTypes,
                    framerate: document.model.timecodeSettings.framerate,
                    showfile: "OnlyCue",
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
    func ma2PushSheet(document: CueListDocument, undoManager: UndoManager?) -> some View {
        modifier(MA2PushSheetPresenter(document: document, undoManager: undoManager))
    }
}
