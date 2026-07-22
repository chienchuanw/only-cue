import Foundation

/// Exports one video's cues to a PotPlayer bookmark file (`.pbf`) body.
///
/// `.pbf` is an INI-style text file; each bookmark is a line under a
/// `[Bookmark]` header:
///
///     [Bookmark]
///     1=<milliseconds>*<title>*
///
/// The three `*`-separated fields are time (ms from the video's 0), title, and
/// thumbnail (left empty). Bookmarks are written in time order with a 1-based
/// index. Times are `round(cue.time * 1000)` — the same 0-based playback seconds
/// OnlyCue stores, so a bookmark lands on the identical frame; the SMPTE
/// `startTimecodeFrames` label offset is deliberately ignored.
///
/// Title is `[Type] Number Name`, e.g. `[Lighting] 12 副歌`; the number is
/// dropped when the cue is unnumbered and the `[Type]` bracket when the type is
/// unknown. `*`, CR, and LF are replaced with a space so a cue title can't break
/// the `*`-delimited / line-based format — only the `.pbf` output is sanitized,
/// never the stored cue.
///
/// Per-Type `isExportEnabled` filtering happens upstream in the writer; this
/// renders exactly the cues it is handed. An empty list yields just the
/// `[Bookmark]` header, matching PotPlayer's empty bookmark file.
enum PBFExporter {

    static func pbf(cues: [Cue], typeNamesByID: [UUID: String]) -> String {
        let sorted = cues.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return (lhs.cueNumber ?? .greatestFiniteMagnitude)
                 < (rhs.cueNumber ?? .greatestFiniteMagnitude)
        }
        var out = "[Bookmark]\n"
        for (index, cue) in sorted.enumerated() {
            let ms = Int((cue.time * 1000).rounded())
            out += "\(index + 1)=\(ms)*\(title(for: cue, typeNamesByID: typeNamesByID))*\n"
        }
        return out
    }

    private static func title(for cue: Cue, typeNamesByID: [UUID: String]) -> String {
        var parts: [String] = []
        if let typeName = typeNamesByID[cue.typeID], !typeName.isEmpty {
            parts.append("[\(typeName)]")
        }
        if let number = cue.cueNumber {
            parts.append(FadeTime.formatNumber(number))
        }
        if !cue.name.isEmpty {
            parts.append(cue.name)
        }
        return sanitize(parts.joined(separator: " "))
    }

    /// Replace the format's control characters — the `*` field delimiter and any
    /// line break — with spaces so a cue title can't corrupt the `.pbf`.
    private static func sanitize(_ title: String) -> String {
        var result = title
        for bad in ["*", "\r", "\n"] {
            result = result.replacingOccurrences(of: bad, with: " ")
        }
        return result
    }
}
