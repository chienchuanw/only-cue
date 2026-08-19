import SwiftUI

/// View modifier that listens for `.sendToMA2Requested` (#683) and presents the batch
/// `MA2BatchPushSheet` (#765) over every song in the project. The notification object
/// (`MediaItem.ID`, or nil = the active item) pre-selects that song; the user checks any
/// others. Target and cue-number writes go through `CueCommands` — never a direct model write.
struct MA2PushSheetPresenter: ViewModifier {

    let document: CueListDocument
    let undoManager: UndoManager?

    @State private var model: MA2BatchPushModel?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .sendToMA2Requested)) { note in
                let preselect = note.object as? MediaItem.ID
                model = makeModel(preselect: preselect)
            }
            .sheet(item: $model) { model in
                MA2BatchPushSheet(
                    model: model,
                    document: document,
                    undoManager: undoManager,
                    cuePointTypes: document.model.cuePointTypes,
                    framerate: document.model.timecodeSettings.framerate,
                    onDismiss: { self.model = nil }
                )
            }
    }

    private func makeModel(preselect: MediaItem.ID?) -> MA2BatchPushModel {
        let songs = document.model.items.map { item in
            MA2BatchPushModel.SongInput(
                itemID: item.id,
                name: item.resolvedName,
                cues: item.cues,
                saved: item.ma2PushTarget
            )
        }
        return MA2BatchPushModel(
            songs: songs,
            activeItemID: document.model.activeItemID,
            preselect: preselect
        )
    }
}

extension View {
    func ma2PushSheet(document: CueListDocument, undoManager: UndoManager?) -> some View {
        modifier(MA2PushSheetPresenter(document: document, undoManager: undoManager))
    }
}
