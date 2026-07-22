import SwiftUI

/// View modifier that listens for `.exportPotPlayerRequested` and routes it to
/// `PotPlayerExportAction`. Same pattern as `BundleExportMenuReceiver`.
struct PotPlayerExportMenuReceiver: ViewModifier {

    @ObservedObject var document: CueListDocument

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportPotPlayerRequested)) { _ in
                PotPlayerExportAction.export(from: document)
            }
    }
}

extension View {
    func potPlayerExportMenuReceiver(document: CueListDocument) -> some View {
        modifier(PotPlayerExportMenuReceiver(document: document))
    }
}
