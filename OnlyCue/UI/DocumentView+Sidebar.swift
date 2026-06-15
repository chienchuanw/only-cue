import SwiftUI

extension DocumentView {

    /// The media sidebar as a floating leading overlay (#539). Slides in/out;
    /// its material background + trailing divider make it read as a panel over
    /// the waveform rather than a column that pushes it. Lives in this extension
    /// so `DocumentView.swift` stays under SwiftLint's `file_length`.
    @ViewBuilder
    var floatingSidebar: some View {
        if sidebarVisible {
            ItemListPane(document: document, onDropURLs: importURLs)
                .frame(width: 240)
                .background(.bar)
                .overlay(alignment: .trailing) { Divider() }
                .shadow(radius: 8, x: 2)
                .transition(.move(edge: .leading))
                .zIndex(1)
        }
    }
}
