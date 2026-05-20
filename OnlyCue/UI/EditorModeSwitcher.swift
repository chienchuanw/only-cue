import SwiftUI

/// The `Cue | Lyric | Show` segmented control shown at the top of the preview
/// pane. Always visible — the mode changes what waveform clicks do, so the user
/// must be able to read it at a glance.
struct EditorModeSwitcher: View {

    let mode: EditorMode
    let setMode: (EditorMode) -> Void

    var body: some View {
        Picker("Editor Mode", selection: selectionBinding) {
            ForEach(EditorMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("editorModeSwitcher")
    }

    private var selectionBinding: Binding<EditorMode> {
        Binding(get: { mode }, set: { setMode($0) })
    }
}
