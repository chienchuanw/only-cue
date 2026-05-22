import SwiftUI

/// View modifier that listens for `.exportCueListRequested` and
/// `.importCueListRequested` and routes them to `CueTransferAction`. Extracted
/// from `DocumentView` so the handlers stay close together and the view stays
/// under SwiftLint's `type_body_length` cap. Same pattern as
/// `TemplateMenuReceiver`.
struct CueTransferMenuReceiver: ViewModifier {

    @ObservedObject var document: CueListDocument
    var undoManager: UndoManager?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportCueListRequested)) { _ in
                CueTransferAction.export(from: document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .importCueListRequested)) { _ in
                CueTransferAction.import(into: document, undoManager: undoManager)
            }
    }
}

extension View {
    func cueTransferMenuReceiver(
        document: CueListDocument,
        undoManager: UndoManager?
    ) -> some View {
        modifier(CueTransferMenuReceiver(document: document, undoManager: undoManager))
    }
}
