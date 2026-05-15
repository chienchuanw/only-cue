import AppKit
import Foundation
import UniformTypeIdentifiers

/// Wires the pure exporter + filter to an `NSSavePanel` and disk write.
/// Extracted from `DocumentView` to keep that struct under SwiftLint's
/// `type_body_length` cap and to keep AppKit-side concerns out of the
/// SwiftUI view body.
enum CueCSVExportAction {

    /// Runs the export flow synchronously: applies the per-Type filter,
    /// formats via the chosen target, opens the save panel, and writes the
    /// result. Throws on disk write failure; bails silently if the user
    /// cancels the panel or no active item exists.
    @MainActor
    static func run(
        model: ProjectModel,
        target: ExportTarget = .csv,
        onlyTypeIDs: Set<UUID> = []
    ) throws {
        guard let item = model.activeItem else { return }
        let typeNamesByID = Dictionary(
            uniqueKeysWithValues: model.cuePointTypes.map { ($0.id, $0.name) }
        )
        let filtered = CueExportFilter.cues(item.cues, onlyTypeIDs: onlyTypeIDs)
        let body = target.format(cues: filtered, typeNamesByID: typeNamesByID)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [target.contentType]
        panel.nameFieldStringValue = "\(item.resolvedName).\(target.fileExtension)"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try body.write(to: url, atomically: true, encoding: .utf8)
    }
}
