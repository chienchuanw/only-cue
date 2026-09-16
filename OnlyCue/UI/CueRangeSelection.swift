import Foundation

/// Resolves a ⇧-click into the inclusive run of rows between the anchor and the
/// clicked row (#790).
///
/// The range is resolved against the **displayed** id order the pane hands in,
/// never against `Cue.ID` or cue time: the user is pointing at rows on screen,
/// so "between" can only mean between them as drawn. That also means a future
/// row-hiding filter needs no change here — only a shorter array.
///
/// Pure, so it is unit-testable and mirrorable in the Windows core, the same
/// split `CueRowTap` uses.
enum CueRangeSelection {

    /// - Parameters:
    ///   - displayed: every row id in the order it is drawn.
    ///   - anchor: the last row selected *without* ⇧. `nil` before the first
    ///     such click. An anchor that is no longer displayed — filtered out, or
    ///     deleted from another pane — must not range from a phantom position.
    ///   - target: the clicked row.
    /// - Returns: the inclusive range, or just `target` when there is no usable
    ///   anchor. The click has to do something, and selecting what was clicked
    ///   is the only answer that does not surprise.
    static func range(in displayed: [Cue.ID],
                      from anchor: Cue.ID?,
                      to target: Cue.ID) -> Set<Cue.ID> {
        guard let anchor,
              let anchorIndex = displayed.firstIndex(of: anchor),
              let targetIndex = displayed.firstIndex(of: target)
        else {
            return [target]
        }
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        return Set(displayed[bounds])
    }
}
