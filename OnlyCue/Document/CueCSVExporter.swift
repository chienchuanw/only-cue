import Foundation

/// Exports a list of cues to RFC 4180 CSV.
///
/// Schema (one row per cue, plus a header row):
///     id,name,time,fadeIn,fadeOut,type,notes
///
/// `time` / `fadeIn` / `fadeOut` are written as decimal seconds matching the
/// in-memory `Cue.time` and `FadeTime.fadeIn` / `.fadeOut` storage. `type` is
/// the human-readable name from the project's `CuePointType` lookup; the
/// column is empty when the type ID is missing from the lookup. Per RFC 4180,
/// values containing commas, quotes, or newlines are wrapped in double quotes
/// with internal quotes doubled.
enum CueCSVExporter {

    static let header = "id,name,time,fadeIn,fadeOut,type,notes"

    static func csv(cues: [Cue], typeNamesByID: [UUID: String]) -> String {
        var out = header + "\n"
        for cue in cues {
            let typeName = typeNamesByID[cue.typeID] ?? ""
            let columns: [String] = [
                cue.id.uuidString,
                escape(cue.name),
                String(cue.time),
                String(cue.fadeTime.fadeIn),
                String(cue.fadeTime.fadeOut),
                escape(typeName),
                escape(cue.notes)
            ]
            out += columns.joined(separator: ",") + "\n"
        }
        return out
    }

    /// RFC 4180 escape: wrap in `"`s if the value contains comma, quote, or
    /// newline; double internal quotes. Plain values pass through untouched
    /// (no surrounding quotes), keeping the output readable for cues with
    /// simple names.
    private static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
        guard needsQuoting else { return value }
        let doubled = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }
}
