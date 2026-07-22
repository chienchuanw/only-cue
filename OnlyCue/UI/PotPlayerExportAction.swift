import AppKit

/// Wires the File menu's **Export PotPlayer Bookmarks…** action. Copies every
/// located video into a chosen folder and writes a paired `.pbf` beside each so
/// PotPlayer (Windows) can auto-load OnlyCue's cues as jump-to bookmarks.
///
/// Mirrors `BundleExportAction`: same source-location + option-C "some files
/// missing" warning + `NSSavePanel` shell, but delegates the write to
/// `PotPlayerBundleWriter` (flat videos + `.pbf`, no `.cuelist`). Not
/// unit-tested (thin I/O); verified by running the app.
enum PotPlayerExportAction {

    @MainActor
    static func export(from document: CueListDocument) {
        let model = document.model

        let sources = model.items.map { item in
            BundleLayout.Source(
                id: item.id,
                name: item.media.displayName,
                url: MediaReveal.revealURL(for: item.media)
            )
        }
        let layout = BundleLayout.plan(sources)

        if !layout.missing.isEmpty, !confirmMissing(count: layout.missing.count) {
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.name.isEmpty ? "Untitled" : model.name
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.nameFieldLabel = "Folder Name:"
        panel.message = "Choose where to save the PotPlayer bookmark folder."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let fileManager = FileManager.default
            // NSSavePanel already confirmed any overwrite; start from a clean folder.
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try PotPlayerBundleWriter.write(layout: layout, model: model, to: destination)
        } catch {
            // Don't leave a half-written folder behind on a mid-copy failure.
            try? FileManager.default.removeItem(at: destination)
            presentError(message: "The PotPlayer bookmarks could not be exported.")
        }
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
        These files couldn’t be located on this Mac, so no bookmarks will be \
        written for them. Export the rest anyway?
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private static func presentError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PotPlayer Export Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
