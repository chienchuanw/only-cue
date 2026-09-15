import Foundation

/// The two cue orders every MA2 generator depends on, in one place so the
/// sequence XML, the timecode XML and the telnet planner cannot drift apart on
/// the rule that keeps them consistent: the sequence is **number**-ordered and
/// the timecode events are **time**-ordered, with each event carrying its cue's
/// number-ordered index. Mirrors `windows/OnlyCue.Core/Ma2/Ma2CueOrdering.cs`.
///
/// Both orders are **total**: equal keys fall back to the cue's position in the
/// input. `sorted(by:)` is documented as not guaranteed stable, so without the
/// fallback the relative order of equal keys is unspecified — and ties are the
/// normal case, not an edge one. Every cue created through `CueCommands` starts
/// unnumbered, and `?? 0` collapses all of them onto the same key (#834).
///
/// The fallback is the input position rather than the cue's `id` on purpose. A
/// Swift `UUID` and a .NET `Guid` do not order the same way — `Guid`'s first
/// three fields are little-endian — so tie-breaking on the identifier would have
/// replaced an unspecified order with a reliably *different* one on the two
/// platforms. Input position is the same on both because both read the same cue
/// array.
///
/// The fallback is here by construction, not by coverage: the golden vectors
/// catch a *different* tie rule, but they cannot catch a *missing* one. Deleting
/// it leaves every test green, because the shipping sort happens to be stable —
/// 14,000 sorts across sizes 3…10,000 and five tie densities produced no
/// observably unstable ordering. What it violates is the documented guarantee,
/// which is exactly the coincidence #834 is about. Do not delete it on the
/// strength of a green run.
enum MA2CueOrdering {

    /// MA2 sequences are number-ordered. An unnumbered cue sorts as 0.
    static func byNumber(_ cues: [Cue]) -> [Cue] {
        ordered(cues) { $0.cueNumber ?? 0 }
    }

    static func byTime(_ cues: [Cue]) -> [Cue] {
        ordered(cues) { $0.time }
    }

    /// Maps each cue id to its 1-based position in number order — the third
    /// `<No>` of a timecode event's cue reference.
    static func sequenceIndexByCueID(_ cues: [Cue]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (position, cue) in byNumber(cues).enumerated() {
            map[cue.id] = position + 1
        }
        return map
    }

    private static func ordered(_ cues: [Cue], by key: (Cue) -> Double) -> [Cue] {
        cues.enumerated()
            .sorted { lhs, rhs in
                let left = key(lhs.element), right = key(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}
