import SwiftUI
import AppKit

/// Listens for `.exportMA2PluginRequested` (#683, Approach C): resolves the
/// item, builds the plugin bundle, and — on a clean pre-flight — saves the two
/// files via an `NSSavePanel`. Blocked pre-flights are surfaced in an alert.
/// Saving the (pre-filled) target back to the document goes through
/// `CueCommands.setMA2PushTarget`, never a direct model write.
struct MA2PluginExportPresenter: ViewModifier {

    let document: CueListDocument
    let undoManager: UndoManager?

    @State private var blockedIssues: [MA2PushPreflight.Issue] = []
    @State private var showingBlock = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportMA2PluginRequested)) { note in
                export(requestedID: note.object as? MediaItem.ID)
            }
            .alert("Cannot export plugin", isPresented: $showingBlock) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(blockedIssues.map(MA2PushSheet.describe).joined(separator: "\n"))
            }
    }

    private func export(requestedID: MediaItem.ID?) {
        let itemID = requestedID ?? document.model.activeItemID
        guard let item = document.model.items.first(where: { $0.id == itemID }) else { return }
        let target = item.ma2PushTarget ?? MA2PushTarget(
            sequenceSlot: 1,
            timecodeSlot: 1,
            executorPage: 1,
            executorNumber: 1,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
        let datetime = ISO8601DateFormatter().string(from: Date())
        switch MA2PushRequestBuilder.pluginOutcome(
            item: item,
            target: target,
            framerate: document.model.timecodeSettings.framerate,
            datetime: datetime
        ) {
        case .blocked(let issues):
            blockedIssues = issues
            showingBlock = true
        case .ready(let bundle):
            // Persist the target (undoably) only for an export that can proceed.
            CueCommands.setMA2PushTarget(target, itemID: item.id, document: document, undoManager: undoManager)
            save(bundle)
        }
    }

    private func save(_ bundle: MA2PluginBundle) {
        let panel = NSSavePanel()
        panel.title = "Export grandMA2 plugin"
        panel.nameFieldStringValue = bundle.manifestFilename
        panel.prompt = "Export"
        panel.message = "Both the .xml and its _PLUGIN.lua are written next to each other."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? MA2PluginWriter.write(bundle, toDirectory: url.deletingLastPathComponent())
    }
}

extension View {
    func ma2PluginExport(document: CueListDocument, undoManager: UndoManager?) -> some View {
        modifier(MA2PluginExportPresenter(document: document, undoManager: undoManager))
    }
}
