import Foundation
import UniformTypeIdentifiers

/// Output formats the export sheet can produce. Adding a future variant is a
/// single-row change here; the `format(cues:typeNamesByID:)` switch gains a
/// branch, the picker gains an option, and `CueCSVExportAction.run` flows
/// through the same notification path.
///
/// MA3 and MA2 are best-effort grandMA-conventional CSV variants — they reuse
/// the same column shape but rename the header row to grandMA conventions
/// (`Cue,Name,Trig Time,Fade In,Fade Out,Type,Note`). See ADR-014 for the
/// caveat: real-world MA users should validate against their console before
/// relying on the format in production.
enum ExportTarget: String, CaseIterable, Identifiable {
    case csv
    case tsv
    case ma3
    case ma2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: "CSV"
        case .tsv: "TSV (tab-delimited)"
        case .ma3: "grandMA3 CSV (best-effort)"
        case .ma2: "grandMA2 CSV (best-effort)"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv, .ma3, .ma2: "csv"
        case .tsv: "tsv"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv, .ma3, .ma2: .commaSeparatedText
        case .tsv: .tabSeparatedText
        }
    }

    func format(cues: [Cue], typeNamesByID: [UUID: String]) -> String {
        switch self {
        case .csv: CueCSVExporter.csv(cues: cues, typeNamesByID: typeNamesByID)
        case .tsv: CueCSVExporter.tsv(cues: cues, typeNamesByID: typeNamesByID)
        case .ma3, .ma2: CueCSVExporter.maCSV(cues: cues, typeNamesByID: typeNamesByID)
        }
    }
}
