import SwiftUI

/// Resolves a cue row's background fill. Matches the Figma Cue Mode list
/// (`318:1228`): unselected rows are clean (no per-row cue-type tint), the
/// **selected** row carries its cue-type tint (the reserved chroma), and the
/// cue at the playhead keeps the achromatic selection highlight — in any mode
/// (#671, was Show-mode only). Pure so the precedence is unit-tested.
enum CueRowFill {

    /// Which of the four fills a row lands on, named rather than rendered.
    ///
    /// The precedence is the contract, and two branches produce the *same*
    /// `Color`: `.current` and `.selectionFallback` both paint `selection`. So a
    /// colour-level comparison cannot distinguish this implementation from one
    /// that tested `isSelected` before `isCurrent` — which would hide the
    /// playhead's cue whenever a different row was selected. Golden vector 8
    /// pins this enum so the Windows port cannot make that mistake silently
    /// (#837).
    enum Resolution: String, Equatable, CaseIterable {
        /// The cue at the playhead — the achromatic selection highlight.
        case current
        /// The selected row's own cue-type tint (the reserved chroma).
        case tint
        /// Selected but with no type colour: the achromatic highlight again.
        case selectionFallback
        /// Idle row — no fill.
        case clear
    }

    /// - Parameters:
    ///   - isSelected: the row is in the list selection.
    ///   - isCurrent: the cue is the one at the playhead (its current section).
    ///   - hasTint: the cue resolves to a type colour.
    ///
    /// The current-cue highlight takes precedence over the manual selection tint,
    /// so the playhead's cue is always visible even when a different row is
    /// selected for editing (#671). A selected cue with no type color falls back
    /// to the achromatic `selection` fill so it stays visible now that the blue
    /// system highlight is gone (#679) — otherwise it would render as `.clear`.
    static func resolution(isSelected: Bool, isCurrent: Bool, hasTint: Bool) -> Resolution {
        if isCurrent { return .current }
        guard isSelected else { return .clear }
        return hasTint ? .tint : .selectionFallback
    }

    /// - Parameters:
    ///   - tint: the cue's type-color tint, or nil when it has no type color.
    ///   - selection: the achromatic selection highlight.
    ///
    /// Pure rendering of `resolution` — the decision lives there, this only
    /// spells it in `Color`.
    static func color(isSelected: Bool,
                      isCurrent: Bool,
                      tint: Color?,
                      selection: Color) -> Color {
        switch resolution(isSelected: isSelected, isCurrent: isCurrent, hasTint: tint != nil) {
        case .current, .selectionFallback:
            return selection
        case .tint:
            // Non-nil by construction: `.tint` is only reached when `hasTint`.
            return tint ?? selection
        case .clear:
            return .clear
        }
    }
}
