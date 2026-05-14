import SwiftUI

struct ItemListPane: View {

    @ObservedObject var document: CueListDocument
    let onDropURLs: ([URL]) -> Void

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if document.model.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(minWidth: 200)
        .accessibilityIdentifier("itemListPane")
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            onDropURLs(urls)
            return true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No media")
                .font(.headline)
            Text("Drag files here or use ⌘O")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("itemListEmptyState")
    }

    private var itemList: some View {
        List(selection: selectionBinding) {
            ForEach(document.model.items) { item in
                ItemRowView(
                    item: item,
                    framerate: document.model.timecodeSettings.framerate,
                    onSetStartTimecode: { frames in
                        CueCommands.setStartTimecode(
                            itemID: item.id,
                            frames: frames,
                            document: document,
                            undoManager: undoManager
                        )
                    }
                )
                .tag(Optional(item.id))
            }
            .onMove(perform: move)
            .onDelete(perform: deleteAtOffsets)
        }
        .onDeleteCommand { deleteSelected() }
    }

    private var selectionBinding: Binding<MediaItem.ID?> {
        Binding(
            get: { document.model.activeItemID },
            set: { newID in
                // SwiftUI's List writes the selection binding from inside the
                // view-update pass; mutating the @Published activeItemID
                // synchronously here triggers the "Publishing changes from
                // within view updates" runtime warning. Defer to the next
                // runloop tick to escape the update pass.
                DispatchQueue.main.async {
                    CueCommands.setActiveItem(id: newID, in: document)
                }
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        CueCommands.reorderItems(
            from: source,
            to: destination,
            document: document,
            undoManager: undoManager
        )
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        for index in offsets {
            guard document.model.items.indices.contains(index) else { continue }
            CueCommands.removeItem(
                id: document.model.items[index].id,
                document: document,
                undoManager: undoManager
            )
        }
    }

    private func deleteSelected() {
        guard let id = document.model.activeItemID else { return }
        CueCommands.removeItem(id: id, document: document, undoManager: undoManager)
    }
}
