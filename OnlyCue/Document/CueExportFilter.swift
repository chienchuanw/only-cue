import Foundation

/// Selects which cues should be included in an export. Sits between a project's
/// cue list and any output format (CSV today; grandMA2/3 later) so the filter
/// stays orthogonal to the exporter.
///
/// Empty `onlyTypeIDs` means "no filter" — the input list passes through. This
/// matches the natural UI default ("export all cues") and keeps callers from
/// having to special-case "user toggled nothing on" before invoking the
/// exporter.
enum CueExportFilter {

    static func cues(_ cues: [Cue], onlyTypeIDs: Set<UUID>) -> [Cue] {
        guard !onlyTypeIDs.isEmpty else { return cues }
        return cues.filter { onlyTypeIDs.contains($0.typeID) }
    }
}
