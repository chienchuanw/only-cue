import Foundation
import UniformTypeIdentifiers

/// Output formats the export sheet can produce. Adding a future MA2/MA3 case
/// is a single-row change here; the `format(cues:typeNamesByID:)` switch
/// gains a branch, the picker gains an option, and `CueExportSheetAction.run`
/// flows through the same notification path.
enum ExportTarget: String, CaseIterable, Identifiable {
    case csv
    case tsv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: "CSV"
        case .tsv: "TSV (tab-delimited)"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .tsv: .tabSeparatedText
        }
    }

    func format(cues: [Cue], typeNamesByID: [UUID: String]) -> String {
        switch self {
        case .csv: CueCSVExporter.csv(cues: cues, typeNamesByID: typeNamesByID)
        case .tsv: CueCSVExporter.tsv(cues: cues, typeNamesByID: typeNamesByID)
        }
    }
}
