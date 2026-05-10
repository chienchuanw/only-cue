import AppKit
import Foundation
import UniformTypeIdentifiers

/// Wires `CueCSVExporter` to an `NSSavePanel` and disk write. Extracted from
/// `DocumentView` to keep that struct under SwiftLint's `type_body_length`
/// cap and to keep AppKit-side concerns out of the SwiftUI view body.
enum CueCSVExportAction {

    /// Runs the export flow synchronously: builds the type-name lookup, opens
    /// a save panel, and writes the CSV. Throws on disk write failure; bails
    /// silently if the user cancels the panel or no active item exists (both
    /// are no-op completions, not errors).
    @MainActor
    static func run(model: ProjectModel) throws {
        guard let item = model.activeItem else { return }
        let typeNamesByID = Dictionary(
            uniqueKeysWithValues: model.cuePointTypes.map { ($0.id, $0.name) }
        )
        let csv = CueCSVExporter.csv(cues: item.cues, typeNamesByID: typeNamesByID)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(item.media.displayName).csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
