import AppKit
import Foundation

/// Wires `TemplateStore` to the File menu's Save Template / Load Template
/// actions. Extracted from `DocumentView` so AppKit-side concerns
/// (NSSavePanel / NSOpenPanel) stay out of the SwiftUI body and the view
/// stays under SwiftLint's `type_body_length` cap.
enum TemplateAction {

    /// Open an `NSSavePanel` pointed at the user's templates directory and
    /// write the project's CuePointType set as a template. No-op if the
    /// project has no types or the user cancels the panel.
    @MainActor
    static func save(model: ProjectModel) throws {
        guard !model.cuePointTypes.isEmpty else { return }
        let dir = TemplateStore.defaultDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let panel = NSSavePanel()
        panel.directoryURL = dir
        panel.nameFieldStringValue = "Template.\(TemplateStore.fileExtension)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let templateName = url.deletingPathExtension().lastPathComponent
        let template = CueListTemplate(name: templateName, cuePointTypes: model.cuePointTypes)
        try TemplateStore.save(template, to: url)
    }

    /// Open an `NSOpenPanel` pointed at the user's templates directory and
    /// append-merge the chosen template into the project. No-op if the user
    /// cancels the panel. The merge appends fresh-UUID copies of the
    /// template's types — see ADR-015.
    @MainActor
    static func load(into document: CueListDocument, undoManager: UndoManager?) throws {
        let dir = TemplateStore.defaultDirectory
        let panel = NSOpenPanel()
        panel.directoryURL = dir
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let template = try TemplateStore.load(from: url)
        for type in template.cuePointTypes {
            var fresh = type
            fresh.id = UUID()
            CueCommands.addCuePointType(fresh, document: document, undoManager: undoManager)
        }
    }

    /// Open an `NSOpenPanel` pointed at the user's templates directory, load the
    /// chosen template, and create a new untitled document pre-loaded with its
    /// CuePointType set. No-op if the user cancels. The template is validated
    /// (decoded) before any document is created — a corrupt file surfaces the
    /// error and creates nothing. The new document picks the template up via
    /// `TemplateStore.pendingNewDocumentTemplate`, which `CueListDocument.init()`
    /// reads and clears.
    @MainActor
    static func newDocument() throws {
        let panel = NSOpenPanel()
        panel.directoryURL = TemplateStore.defaultDirectory
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        TemplateStore.pendingNewDocumentTemplate = try TemplateStore.load(from: url)
        NSDocumentController.shared.newDocument(nil)
    }
}
