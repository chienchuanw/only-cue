import SwiftUI

extension CueListPane {

    /// The cue's type-color tint at the row-tint opacity, or clear when the
    /// cue has no resolvable color.
    func rowTint(for cue: Cue) -> Color {
        guard let hex = document.model.colorHex(for: cue),
              let base = Color(hex: hex) else {
            return Color.clear
        }
        return base.opacity(CueListLayout.rowTintOpacity)
    }

    /// The resolved Show-mode GO-by-type filter (#657): nil = All cues. Non-nil
    /// only in Show mode (`isReadOnly`) when the stored id still matches a live
    /// cue type — "" or a deleted type read as All. Shared with `DocumentView`
    /// via the per-window `@SceneStorage("onlycue.showGoTypeID")`.
    ///
    /// Must stay equivalent to `DocumentView.showGoTypeID`, which gates on
    /// `editorMode == .show`: `isReadOnly` is passed `true` only from the `.show`
    /// case of `ModeAwareInspector`, so the two agree today. Keep that invariant
    /// if a future mode ever renders a read-only cue list.
    var showGoTypeID: CuePointType.ID? {
        guard isReadOnly,
              let id = UUID(uuidString: showGoTypeIDRaw),
              document.model.cuePointTypes.contains(where: { $0.id == id })
        else { return nil }
        return id
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
        guard let selected = showGoTypeID, cue.typeID != selected else { return 1 }
        return CueListLayout.dimmedRowOpacity
    }

    /// A row's background. Unselected rows are clean (Figma `318:1228`); the
    /// selected row carries its cue-type tint; in Show mode the cue currently
    /// at the playhead keeps the achromatic selection highlight.
    func rowBackground(for cue: Cue) -> Color {
        CueRowFill.color(
            isSelected: selection.contains(cue.id),
            isReadOnly: isReadOnly,
            isCurrent: cue.id == currentCueID,
            tint: rowTint(for: cue),
            selection: DS.Color.selection
        )
    }
}
