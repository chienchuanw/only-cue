import SwiftUI

/// The right inspector pane, swapped by `EditorMode`: the cue list (Cue), the
/// lyrics pane (Lyric), and the cue list (Show — read-only styling arrives in
/// the Show-mode leaf).
struct ModeAwareInspector: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    let editorMode: EditorMode
    @Binding var cueSelection: Set<Cue.ID>
    @Binding var lyricsCursor: LyricsAuthoringCursor

    var body: some View {
        switch editorMode {
        case .cue:
            CueListPane(document: document, engine: engine, selection: $cueSelection)
        case .lyric:
            LyricsInspectorPane(document: document, engine: engine, lyricsCursor: $lyricsCursor)
        case .show:
            CueListPane(document: document, engine: engine, selection: $cueSelection, isReadOnly: true)
        }
    }
}
