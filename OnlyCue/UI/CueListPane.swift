import SwiftUI

struct CueListPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine

    @Environment(\.undoManager) private var undoManager
    @State private var selection: Cue.ID?

    private var cues: [Cue] { document.model.activeItem?.cues ?? [] }

    var body: some View {
        Group {
            if cues.isEmpty {
                emptyState
            } else {
                cueList
            }
        }
        .frame(minWidth: 240)
        .accessibilityIdentifier("cueListPane")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No cues yet")
                .font(.headline)
            Text(document.model.activeItem == nil
                 ? "Import or select a media item first"
                 : "Press M to add one at the playhead")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("cueListEmptyState")
    }

    private var cueList: some View {
        List(selection: $selection) {
            ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                CueRowView(
                    index: index + 1,
                    cue: cue,
                    onRename: { newName in
                        CueCommands.rename(cueId: cue.id, to: newName, document: document, undoManager: undoManager)
                    },
                    onRecolor: { newHex in
                        CueCommands.recolor(cueId: cue.id, to: newHex, document: document, undoManager: undoManager)
                    }
                )
                .tag(cue.id)
            }
            .onDelete(perform: deleteAtOffsets)
        }
        .onDeleteCommand { deleteSelected() }
        .onChange(of: selection) { _, newValue in
            guard
                let id = newValue,
                let cue = cues.first(where: { $0.id == id })
            else { return }
            Task { await engine.seek(to: cue.time) }
        }
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        for index in offsets {
            guard cues.indices.contains(index) else { continue }
            let cue = cues[index]
            CueCommands.delete(cueId: cue.id, document: document, undoManager: undoManager)
        }
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        CueCommands.delete(cueId: id, document: document, undoManager: undoManager)
        selection = nil
    }
}
