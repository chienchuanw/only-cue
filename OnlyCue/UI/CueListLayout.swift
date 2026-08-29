import SwiftUI

enum CueListLayout {
    static let rowHorizontalSpacing: CGFloat = 8
    /// Horizontal edge padding on the header row. Shared with
    /// `headerHorizontalChrome` so the #297 width floor can never silently
    /// diverge from the padding actually rendered.
    static let rowHorizontalPadding: CGFloat = 8
    static let rowTintOpacity: Double = 0.18

    /// The horizontal inset macOS's `List` adds to every row on top of the
    /// row's own padding. The column header lives *outside* the `List`, so it
    /// must mirror this inset to line its columns up with the row values below
    /// (`listRowInsets` / `.listStyle(.plain)` do not remove it on macOS). The
    /// `CueListColumnAlignmentUITests` regression guard fails if it drifts.
    static let listRowHorizontalInset: CGFloat = 16

    /// Opacity of a cue row whose type differs from the Show-mode GO-by-type
    /// filter — dimmed but still visible and hittable (#657).
    static let dimmedRowOpacity: Double = 0.35

    /// Basis for `rowLeadingGutter` — kept so the header/row column alignment
    /// and the #297 floor are unchanged after the swatch became a stripe.
    static let swatchDiameter: CGFloat = 8

    /// Cue-type colour stripe on a row's left edge (Figma `318:1326` TypeBar);
    /// sits inside `rowLeadingGutter`, so it doesn't affect the header floor.
    static let typeStripeWidth: CGFloat = 5

    /// The leading offset of a row's first column (Time): the row's leading
    /// padding (`DS.Space.xs / 2`) + the swatch + the swatch-to-content gap
    /// (`DS.Space.xs`). The header reserves the same gutter (Figma's empty
    /// swatch slot, `318:1320`) so its TIME/#/NAME/FADE labels align with the
    /// row columns.
    static let rowLeadingGutter: CGFloat = DS.Space.xs / 2 + swatchDiameter + DS.Space.xs

    /// Clickable width of the stripe (#786). The stripe is drawn 5pt wide but
    /// is now the row's select/seek handle, so its hit area widens to fill the
    /// gutter — and stops exactly there, because the `#` column's text starts
    /// at `rowLeadingGutter` and a wider target would swallow its clicks.
    static let typeStripeHitWidth: CGFloat = rowLeadingGutter

    /// Non-column horizontal cost of the header row: the 2 inter-column gaps
    /// (`rowHorizontalSpacing` each, for `# · Name · Info`) plus the leading
    /// swatch gutter and the trailing edge padding. The Name column is flexible
    /// with no enforced intrinsic minimum, so it compresses to ~0 and
    /// contributes nothing.
    static let headerHorizontalChrome: CGFloat =
        2 * rowHorizontalSpacing + rowLeadingGutter + rowHorizontalPadding
            + 2 * listRowHorizontalInset

    /// The cue-list header's guaranteed-compressible minimum width — the
    /// value the outer `NSSplitView` sees as the pane's hard floor. Issue
    /// #297: this must never exceed `CueListInspectorMetrics.minWidth`, or
    /// the splitter cannot reach the 240 column minimum without the content
    /// demanding more and feeding the constraint-update loop. Header and rows
    /// share the same leading swatch gutter (`rowLeadingGutter`), so the
    /// header is the binding floor; the two fixed columns are `#` and `Info`
    /// (Name is flexible), so the floor stays ≤ 240 (40+72+chrome).
    static var headerMinimumWidth: CGFloat {
        CueListColumnWidths.numberRange.lowerBound
            + CueListColumnWidths.infoRange.lowerBound
            + headerHorizontalChrome
    }
}
