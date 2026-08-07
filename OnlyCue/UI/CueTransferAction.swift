import AppKit
import UniformTypeIdentifiers

/// Wires the Cue menu's Export / Import Cue List actions to the `.occues`
/// interchange format. Holds the AppKit-side concerns — `NSSavePanel`,
/// `NSOpenPanel`, and the mismatch / conflict `NSAlert`s — out of the SwiftUI
/// body. Same pattern as `TemplateAction`. Pure transfer logic lives in
/// `CueListTransfer`; the undoable model write is `CueCommands.importCueList`.
enum CueTransferAction {

    /// Export the active item's cue list to a user-chosen `.occues` file.
    /// No-op when there is no active item or the user cancels the panel.
    @MainActor
    static func export(from document: CueListDocument) {
        guard let item = document.model.activeItem else { return }
        let export = CueListTransfer.makeExport(
            of: item,
            projectTypes: document.model.cuePointTypes
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.cueListExport]
        panel.nameFieldStringValue = "\(item.resolvedName) cues.occues"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CueListTransfer.encode(export).write(to: url)
        } catch {
            presentError(message: String(localized: "The cue list could not be exported."))
        }
    }

    /// Import a `.occues` file onto the active item. Runs the mismatch check and
    /// the conflict dialog, then delegates to `CueCommands.importCueList`.
    /// No-op when there is no active item or the user cancels.
    @MainActor
    static func `import`(into document: CueListDocument, undoManager: UndoManager?) {
        guard let item = document.model.activeItem else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.cueListExport]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let export: CueListExport
        do {
            export = try CueListTransfer.decode(try Data(contentsOf: url))
        } catch let error as CueListTransfer.TransferError {
            presentError(message: message(for: error))
            return
        } catch {
            presentError(message: String(localized: "The cue list file could not be read."))
            return
        }

        if !CueListTransfer.mediaMatches(export, item),
           !confirmMismatch(export: export, item: item) {
            return
        }

        let mode: CueCommands.CueImportMode
        if item.cues.isEmpty {
            mode = .replace
        } else {
            switch conflictChoice() {
            case .some(true): mode = .replace
            case .some(false): mode = .add
            case .none: return // cancelled
            }
        }

        CueCommands.importCueList(export, mode: mode, document: document, undoManager: undoManager)
    }

    // MARK: - Alerts

    /// Mismatch confirmation. Returns true to proceed with the import.
    @MainActor
    private static func confirmMismatch(export: CueListExport, item: MediaItem) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "This cue list is from a different song")
        alert.informativeText = String(localized: """
        The cue list was exported from “\(export.sourceMedia.displayName)” \
        (\(formatted(export.sourceMedia.duration))). The selected song is \
        “\(item.resolvedName)” (\(formatted(item.media.duration))).

        Import the cues anyway?
        """)
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Conflict dialog for a non-empty target. Returns `true` for Replace,
    /// `false` for Add, `nil` for Cancel.
    @MainActor
    private static func conflictChoice() -> Bool? {
        let alert = NSAlert()
        alert.messageText = String(localized: "This song already has cues")
        alert.informativeText = String(
            localized: "Replace the existing cues with the imported ones, or add the imported cues alongside them?"
        )
        alert.addButton(withTitle: String(localized: "Replace"))  // .alertFirstButtonReturn
        alert.addButton(withTitle: String(localized: "Add"))      // .alertSecondButtonReturn
        alert.addButton(withTitle: String(localized: "Cancel"))   // .alertThirdButtonReturn
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    @MainActor
    private static func presentError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Cue List Import Failed")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private static func message(for error: CueListTransfer.TransferError) -> String {
        switch error {
        case .unsupportedFormatVersion:
            return String(localized: "This cue list was created by a newer version of OnlyCue and can't be opened.")
        case .malformedPayload:
            return String(localized: "The file is not a valid OnlyCue cue list.")
        }
    }

    /// `m:ss` rendering of a media duration for the mismatch alert.
    private static func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
