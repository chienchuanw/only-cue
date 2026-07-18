import SwiftUI

/// Resolves a cue row's background fill. Matches the Figma Cue Mode list
/// (`318:1228`): unselected rows are clean (no per-row cue-type tint), the
/// **selected** row carries its cue-type tint (the reserved chroma), and the
/// cue at the playhead keeps the achromatic selection highlight — in any mode
/// (#671, was Show-mode only). Pure so the precedence is unit-tested.
enum CueRowFill {

    /// - Parameters:
    ///   - isSelected: the row is in the list selection.
    ///   - isCurrent: the cue is the one at the playhead (its current section).
    ///   - tint: the cue's type-color tint, or nil when it has no type color.
    ///   - selection: the achromatic selection highlight.
    ///
    /// The current-cue highlight takes precedence over the manual selection tint,
    /// so the playhead's cue is always visible even when a different row is
    /// selected for editing (#671). A selected cue with no type color falls back
    /// to the achromatic `selection` fill so it stays visible now that the blue
    /// system highlight is gone (#679) — otherwise it would render as `.clear`.
    static func color(isSelected: Bool,
                      isCurrent: Bool,
                      tint: Color?,
                      selection: Color) -> Color {
        if isCurrent { return selection }
        guard isSelected else { return .clear }
        return tint ?? selection
    }
}
