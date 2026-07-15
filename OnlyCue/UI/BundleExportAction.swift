import AppKit

/// Wires the File menu's **Export Bundle…** action (#640). Collects the project
/// and every audio file it references into a self-contained folder:
///
/// ```
/// My Show/
/// ├── My Show.cuelist   # bundlePath stamped on each item
/// └── media/            # every referenced file, deduped, collision-renamed
/// ```
///
/// The recipient opens the ordinary `.cuelist` inside and the media auto-attaches
/// (#641). Holds the AppKit concerns — `NSSavePanel`, the option-C `NSAlert` —
/// out of the SwiftUI body; the pure layout is `BundleLayout`. Not unit-tested
/// (thin I/O); verified by running the app.
enum BundleExportAction {

    @MainActor
    static func export(from document: CueListDocument) {
        let model = document.model

        // Locate every item's source file with the two-step locator (#636/#638).
        let sources = model.items.map { item in
            BundleLayout.Source(
                id: item.id,
                name: item.media.displayName,
                url: MediaReveal.revealURL(for: item.media)
            )
        }
        let layout = BundleLayout.plan(sources)

        // Option C: warn before writing when some files can't be included.
        if !layout.missing.isEmpty, !confirmMissing(count: layout.missing.count) {
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.name.isEmpty ? "Untitled" : model.name
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.nameFieldLabel = "Bundle Name:"
        panel.message = "Choose where to save the bundle folder."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try write(layout: layout, model: model, to: destination)
        } catch {
            presentError(message: "The bundle could not be exported.")
        }
    }

    /// Writes `<destination>/` with `media/` and the `.cuelist`. `destination`'s
    /// last path component names both the folder (from `NSSavePanel`) and the
    /// `.cuelist` inside it.
    @MainActor
    private static func write(layout: BundleLayout, model: ProjectModel, to destination: URL) throws {
        let fileManager = FileManager.default
        // NSSavePanel already confirmed any overwrite; start from a clean folder.
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try BundleWriter.write(layout: layout, model: model, to: destination)
    }

    /// Option-C confirmation. Returns true to export the rest anyway.
    @MainActor
    private static func confirmMissing(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1
            ? "1 media file can’t be included"
            : "\(count) media files can’t be included"
        alert.informativeText = """
        These files couldn’t be located on this Mac, so they won’t be in the \
        bundle and the recipient will need to relink them. Export the rest anyway?
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private static func presentError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Bundle Export Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
