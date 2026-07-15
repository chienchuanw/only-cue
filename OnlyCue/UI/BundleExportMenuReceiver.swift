import SwiftUI

/// View modifier that listens for `.exportBundleRequested` and routes it to
/// `BundleExportAction` (#640). Same pattern as `CueTransferMenuReceiver`.
struct BundleExportMenuReceiver: ViewModifier {

    @ObservedObject var document: CueListDocument

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportBundleRequested)) { _ in
                BundleExportAction.export(from: document)
            }
    }
}

extension View {
    func bundleExportMenuReceiver(document: CueListDocument) -> some View {
        modifier(BundleExportMenuReceiver(document: document))
    }
}
