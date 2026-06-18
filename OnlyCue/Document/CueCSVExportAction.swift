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
        panel.nameFieldStringValue = suggestedFilename(forItemName: item.resolvedName, target: target)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Suggested save-panel filename: the media item's name with its own
    /// extension stripped, plus the export extension — so "abc.mp3" → "abc.csv",
    /// not "abc.mp3.csv" (#569). Falls back to the raw name if stripping leaves
    /// it empty (e.g. a dotfile-style name).
    static func suggestedFilename(forItemName name: String, target: ExportTarget) -> String {
        let base = (name as NSString).deletingPathExtension
        let stem = base.isEmpty ? name : base
        return "\(stem).\(target.fileExtension)"
    }
}
