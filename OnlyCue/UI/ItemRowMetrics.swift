import CoreGraphics

/// Pure layout metrics for the sidebar media row (`ItemRowView`), pinned to
/// Figma 318:1238 / component set 77:43. Mirrors the CueRowFill / PreviewLayout
/// pattern: keeping the load-bearing numbers and the hover rule as plain values
/// gives the single-line layout a renderer-independent fidelity gate.
enum ItemRowMetrics {

    /// Leading kind-icon glyph box — 14×14 in Figma.
    static let iconSize: CGFloat = 14

    /// Clip-length type size — Roboto Mono 10 (text-tertiary) in Figma.
    static let durationFontSize: CGFloat = 10

    /// The trailing edit pencil is invisible at rest (Hovered=False) and fades
    /// fully in on row hover (Hovered=True). It stays in the view tree at
    /// opacity 0 — never `if`/`.hidden()` — so the row never reflows on hover
    /// and the `inlineEditMedia-<id>` accessibility element remains reachable
    /// by automation.
    static func pencilOpacity(isHovered: Bool) -> Double {
        isHovered ? 1 : 0
    }
}
