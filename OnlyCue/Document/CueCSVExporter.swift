import Foundation

/// Exports a list of cues to delimiter-separated text (CSV or TSV).
///
/// Schema (one row per cue, plus a header row):
///     id,name,time,fadeIn,fadeOut,type,notes
///
/// `time` / `fadeIn` / `fadeOut` are written as decimal seconds matching the
/// in-memory `Cue.time` and `FadeTime.fadeIn` / `.fadeOut` storage. `type` is
/// the human-readable name from the project's `CuePointType` lookup; the
/// column is empty when the type ID is missing from the lookup.
///
/// Escape rules follow RFC 4180: wrap values in double quotes if they contain
/// the active delimiter, a quote, or a newline; double internal quotes. The
/// active delimiter is whichever the caller picked (comma for CSV, tab for
/// TSV) — TSV values containing commas pass through unescaped because commas
/// aren't column separators in TSV.
enum CueCSVExporter {

    static let columns = ["id", "name", "time", "fadeIn", "fadeOut", "type", "notes"]

    static func csv(cues: [Cue], typeNamesByID: [UUID: String]) -> String {
        format(cues: cues, typeNamesByID: typeNamesByID, delimiter: ",")
    }

    static func tsv(cues: [Cue], typeNamesByID: [UUID: String]) -> String {
        format(cues: cues, typeNamesByID: typeNamesByID, delimiter: "\t")
    }

    private static func format(
        cues: [Cue],
        typeNamesByID: [UUID: String],
        delimiter: String
    ) -> String {
        var out = columns.joined(separator: delimiter) + "\n"
        for cue in cues {
            let typeName = typeNamesByID[cue.typeID] ?? ""
            let row: [String] = [
                cue.id.uuidString,
                escape(cue.name, delimiter: delimiter),
                String(cue.time),
                String(cue.fadeTime.fadeIn),
                String(cue.fadeTime.fadeOut),
                escape(typeName, delimiter: delimiter),
                escape(cue.notes, delimiter: delimiter)
            ]
            out += row.joined(separator: delimiter) + "\n"
        }
        return out
    }

    /// Wrap in `"`s if the value contains the active delimiter, a quote, or a
    /// newline; double internal quotes. Plain values pass through untouched.
    private static func escape(_ value: String, delimiter: String) -> String {
        let needsQuoting = value.contains(delimiter) || value.contains("\"") || value.contains("\n")
        guard needsQuoting else { return value }
        let doubled = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }

    // Legacy header (kept so tests pinning the exact CSV header continue to
    // pass without churn). Equivalent to `columns.joined(separator: ",")`.
    static let header = "id,name,time,fadeIn,fadeOut,type,notes"
}
