import Foundation

/// Resolves the Show-mode GO-by-type filter (#657) from the raw per-window
/// `@SceneStorage("onlycue.showGoTypeID")` string: `nil` means *All cues*.
///
/// Extracted from the two view properties that used to compute it independently
/// — `CueListPane.showGoTypeID` and `DocumentView.showGoTypeID` — which had to
/// agree or the row dimming would highlight a different type than GO actually
/// walked. That invariant was previously carried by a comment asking a human to
/// notice; now there is one function (#837).
///
/// The two call sites spell the mode differently: `CueListPane` knows only
/// `isReadOnly`, `DocumentView` knows `editorMode == .show`. They agree today
/// because `isReadOnly` is passed `true` only from the `.show` case of
/// `ModeAwareInspector`. The parameter is named for the *meaning* rather than
/// either spelling, so a future mode that renders a read-only cue list has to
/// decide deliberately rather than inherit the filter by accident.
enum CueListGoFilter {

    /// - Parameters:
    ///   - rawID: the stored scene-storage string. `""` is its default and reads
    ///     as All cues.
    ///   - types: the document's live cue types. An id naming a type that has
    ///     since been deleted also reads as All rather than filtering the list
    ///     down to nothing.
    static func resolve(rawID: String, types: [CuePointType], isShowMode: Bool) -> CuePointType.ID? {
        guard isShowMode,
              let id = UUID(uuidString: rawID),
              types.contains(where: { $0.id == id })
        else { return nil }
        return id
    }
}

/// Row-content opacity under the GO-by-type filter (#657): rows of another type
/// dim rather than disappear, so the walked type stands out while the
/// surrounding cues stay readable.
///
/// `dimmed` is injected rather than read from `CueListLayout` so the rule is
/// pure — the golden vector seats the constant it wants and the design token
/// stays a macOS concern (#837).
enum CueListRowOpacity {

    static func value(cueTypeID: CuePointType.ID, filter: CuePointType.ID?, dimmed: Double) -> Double {
        guard let filter, cueTypeID != filter else { return 1 }
        return dimmed
    }
}

/// The cue list's empty-state instruction. Two different dead ends need two
/// different instructions: with no media loaded there is nothing to place a cue
/// against, so "press M" would be a lie (#837).
enum CueListEmptyState {

    static func message(hasActiveItem: Bool) -> String {
        hasActiveItem
            ? "Press M to add a cue at the playhead."
            : "Import a media file to start adding cues."
    }
}
