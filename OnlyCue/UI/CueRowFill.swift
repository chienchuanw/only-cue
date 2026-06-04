import SwiftUI

/// Resolves a cue row's background fill. Matches the Figma Cue Mode list
/// (`318:1228`): unselected rows are clean (no per-row cue-type tint), the
/// **selected** row carries its cue-type tint (the reserved chroma), and in
/// Show mode the cue currently at the playhead keeps the achromatic selection
/// highlight. Pure so the precedence is unit-tested without a view.
enum CueRowFill {

    /// - Parameters:
    ///   - isSelected: the row is in the list selection.
    ///   - isReadOnly: the list is read-only (Show mode).
    ///   - isCurrent: the cue is the one playing at the playhead.
    ///   - tint: the cue's type-color tint.
    ///   - selection: the achromatic selection highlight.
    static func color(isSelected: Bool,
                      isReadOnly: Bool,
                      isCurrent: Bool,
                      tint: Color,
                      selection: Color) -> Color {
        if isReadOnly, isCurrent { return selection }
        return isSelected ? tint : .clear
    }
}
