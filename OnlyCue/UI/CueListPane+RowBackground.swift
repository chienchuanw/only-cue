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

    /// The cue currently "active" at the playhead — emphasized in Show mode.
    var currentCueID: Cue.ID? {
        document.model.activeItem?.activeCue(at: engine.currentTime)?.id
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
