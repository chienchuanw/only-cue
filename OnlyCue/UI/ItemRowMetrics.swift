import SwiftUI

/// Pure layout metrics for the sidebar media row (`ItemRowView`), pinned to
/// Figma 318:1238 / component set 77:43. Mirrors the CueRowFill / PreviewLayout
/// pattern: keeping the load-bearing numbers and the hover rule as plain values
/// gives the single-line layout a renderer-independent fidelity gate.
enum ItemRowMetrics {

    /// Leading kind-icon glyph box — 14×14 in Figma.
    static let iconSize: CGFloat = 14

    /// The user's colour tag as a full-height leading stripe (Figma `77:43`
    /// `color-stripe`, #782). Equal to `CueListLayout.typeStripeWidth` so the
    /// two colour idioms read as one mechanism; declared here rather than
    /// borrowed, because `CueListLayout` belongs to the cue pane and reaching
    /// across panes for a constant would couple them.
    static let colorStripeWidth: CGFloat = 5

    /// Leading inset of the row's content — the stripe plus breathing room, so
    /// the colour never crowds the kind icon (Figma `77:43` `paddingLeft` 13).
    ///
    /// Reserved on *every* row, tagged or not, mirroring
    /// `CueListLayout.rowLeadingGutter`. Insetting only tagged rows would make
    /// the whole row's text jump sideways on every tag and untag.
    static let colorGutter: CGFloat = colorStripeWidth + DS.Space.sm

    /// Clip-length type size — Roboto Mono 10 (text-tertiary) in Figma. Reads
    /// from the DS token the row renders, so the gate can't pin a stale copy.
    static let durationFontSize: CGFloat = DS.Text.monoLabelSize

    /// The trailing edit pencil is invisible at rest (Hovered=False) and fades
    /// fully in on row hover (Hovered=True). It stays in the view tree at
    /// opacity 0 — never `if`/`.hidden()` — so the row never reflows on hover
    /// and the `inlineEditMedia-<id>` accessibility element remains reachable
    /// by automation.
    static func pencilOpacity(isHovered: Bool) -> Double {
        isHovered ? 1 : 0
    }
}
