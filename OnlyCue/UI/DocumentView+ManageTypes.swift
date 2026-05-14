import SwiftUI

/// Hosts the `TypeManagementSheet` so the menu-bar entry can drive it from
/// outside the per-cue inspector. The state and observer live on a modifier
/// so `DocumentView` itself stays under the SwiftLint type-body length cap.
private struct ManageTypesSheetModifier: ViewModifier {

    @ObservedObject var document: CueListDocument
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .manageTypesRequested)) { _ in
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                TypeManagementSheet(document: document)
            }
    }
}

extension View {
    func manageTypesSheet(document: CueListDocument) -> some View {
        modifier(ManageTypesSheetModifier(document: document))
    }
}
