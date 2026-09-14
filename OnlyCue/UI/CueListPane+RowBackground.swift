import SwiftUI

extension CueListPane {

    /// The cue's type-color tint at the row-tint opacity, or nil when the cue
    /// has no resolvable color (a selected uncolored cue then falls back to the
    /// achromatic selection highlight in `CueRowFill`, #679).
    func rowTint(for cue: Cue) -> Color? {
        guard let hex = document.model.colorHex(for: cue),
              let base = Color(hex: hex) else {
            return nil
        }
        return base.opacity(CueListLayout.rowTintOpacity)
    }

    /// The resolved Show-mode GO-by-type filter (#657): nil = All cues. Shared
    /// with `DocumentView` via the per-window
    /// `@SceneStorage("onlycue.showGoTypeID")` — and now via the same function,
    /// so the two cannot drift (#837). `isReadOnly` is passed `true` only from
    /// the `.show` case of `ModeAwareInspector`, which is what makes it the
    /// right argument for `isShowMode`.
    var showGoTypeID: CuePointType.ID? {
        CueListGoFilter.resolve(
            rawID: showGoTypeIDRaw,
            types: document.model.cuePointTypes,
            isShowMode: isReadOnly
        )
    }

    /// The cue currently "active" at the playhead — emphasized in Show mode.
    /// Honours the GO-by-type filter so the highlight tracks the same cue GO
    /// walks (#657).
    var currentCueID: Cue.ID? {
        document.model.activeItem?.activeCue(at: engine.currentTime, typeID: showGoTypeID)?.id
    }

    /// Row content opacity: rows whose type differs from the selected GO filter
    /// are dimmed (still visible) so the walked type stands out (#657). Full
    /// opacity when no filter is active (All / non-Show mode).
    func rowOpacity(for cue: Cue) -> Double {
        CueListRowOpacity.value(
            cueTypeID: cue.typeID,
            filter: showGoTypeID,
            dimmed: CueListLayout.dimmedRowOpacity
        )
    }

    /// A row's background. Unselected rows are clean (Figma `318:1228`); the
    /// selected row carries its cue-type tint; in Show mode the cue currently
    /// at the playhead keeps the achromatic selection highlight.
    func rowBackground(for cue: Cue) -> Color {
        CueRowFill.color(
            isSelected: selection.contains(cue.id),
            isCurrent: cue.id == currentCueID,
            tint: rowTint(for: cue),
            selection: DS.Color.selection
        )
    }
}
