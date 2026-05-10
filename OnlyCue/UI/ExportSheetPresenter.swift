import SwiftUI

/// View modifier that listens for `.exportCuesToCSVRequested`, shows the
/// `ExportSheet`, and runs `CueCSVExportAction` on confirm. Extracted from
/// `DocumentView` so the sheet's local state (target + selected types) lives
/// next to its presentation, and `DocumentView` stays under SwiftLint's
/// `type_body_length` cap.
struct ExportSheetPresenter: ViewModifier {

    let model: ProjectModel
    @Binding var pendingErrorMessage: String?

    @State private var isPresented = false
    @State private var target: ExportTarget = .csv
    @State private var selectedTypeIDs: Set<UUID> = []

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportCuesToCSVRequested)) { _ in
                target = .csv
                selectedTypeIDs = []
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                ExportSheet(
                    cuePointTypes: model.cuePointTypes,
                    target: $target,
                    selectedTypeIDs: $selectedTypeIDs,
                    onCancel: { isPresented = false },
                    onConfirm: confirm
                )
            }
    }

    private func confirm() {
        isPresented = false
        do {
            try CueCSVExportAction.run(
                model: model,
                target: target,
                onlyTypeIDs: selectedTypeIDs
            )
        } catch {
            pendingErrorMessage = error.localizedDescription
        }
    }
}

extension View {
    func exportSheet(
        model: ProjectModel,
        pendingErrorMessage: Binding<String?>
    ) -> some View {
        modifier(ExportSheetPresenter(model: model, pendingErrorMessage: pendingErrorMessage))
    }
}
