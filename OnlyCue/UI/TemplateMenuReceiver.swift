import SwiftUI

/// View modifier that listens for `.saveTemplateRequested` and
/// `.loadTemplateRequested` and routes them to `TemplateAction`. Extracted
/// from `DocumentView` so the two handlers stay close to each other and the
/// view stays under SwiftLint's `type_body_length` cap. Same pattern as
/// `ExportSheetPresenter`.
struct TemplateMenuReceiver: ViewModifier {

    @ObservedObject var document: CueListDocument
    @Binding var pendingErrorMessage: String?
    var undoManager: UndoManager?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .saveTemplateRequested)) { _ in
                do {
                    try TemplateAction.save(model: document.model)
                } catch {
                    pendingErrorMessage = error.localizedDescription
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .loadTemplateRequested)) { _ in
                do {
                    try TemplateAction.load(into: document, undoManager: undoManager)
                } catch {
                    pendingErrorMessage = error.localizedDescription
                }
            }
    }
}

extension View {
    func templateMenuReceiver(
        document: CueListDocument,
        pendingErrorMessage: Binding<String?>,
        undoManager: UndoManager?
    ) -> some View {
        modifier(TemplateMenuReceiver(
            document: document,
            pendingErrorMessage: pendingErrorMessage,
            undoManager: undoManager
        ))
    }
}
