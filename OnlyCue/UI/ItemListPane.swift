import AppKit
import SwiftUI

struct ItemListPane: View {

    @ObservedObject var document: CueListDocument
    let onDropURLs: ([URL]) -> Void

    /// Gates the per-clip "Mute LTC" context-menu item to when LTC routing is on
    /// (#663). Observing the singleton keeps the menu in sync with Preferences.
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared
    @Environment(\.undoManager) private var undoManager
    @State private var editingItemID: MediaItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Audit §6.1: pin the `MEDIA` caption above the sidebar's content
            // (or its empty-state affordance) so the section identity is
            // visible whether or not media has been imported.
            Text("Media")
                .dsSectionHeader()
                // Align the caption to the row content gutter (~16pt) per Figma
                // 318:1239, not the pane edge.
                .padding(.leading, DS.Space.lg)
                .padding(.trailing, DS.Space.sm)
                .padding(.vertical, DS.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("itemListSectionCaption")
            if document.model.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        // Figma 318:1238: the sidebar is a fixed 240pt column (was minWidth 200,
        // which let it collapse below the design width).
        .frame(minWidth: 240)
        .background(DS.Color.panel)
        .accessibilityIdentifier("itemListPane")
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            onDropURLs(urls)
            return true
        }
        .sheet(item: editingItemBinding) { editing in
            MediaEditSheet(
                item: editing.item,
                framerate: document.model.timecodeSettings.framerate,
                onSave: { alt, frames, muted, playsOriginal in
                    CueCommands.updateMediaItem(
                        id: editing.item.id,
                        edit: MediaItemEdit(
                            alternateName: alt,
                            startTimecodeFrames: frames,
                            ltcMuted: muted,
                            playsOriginalSourceAudio: playsOriginal
                        ),
                        document: document,
                        undoManager: undoManager
                    )
                    editingItemID = nil
                },
                onCancel: { editingItemID = nil },
                onRedetectLTC: {
                    // Forget + drop the cache so the resolve re-scans from scratch.
                    CueCommands.clearRememberedLTC(forItemID: editing.item.id, document: document)
                    StripedTimecodeCache.shared.invalidate(editing.item.id)
                },
                onClearLTC: {
                    CueCommands.clearRememberedLTC(forItemID: editing.item.id, document: document)
                }
            )
        }
    }

    private struct EditingTarget: Identifiable {
        let item: MediaItem
        var id: MediaItem.ID { item.id }
    }

    private var editingItemBinding: Binding<EditingTarget?> {
        Binding(
            get: {
                guard let id = editingItemID,
                      let item = document.model.items.first(where: { $0.id == id })
                else { return nil }
                return EditingTarget(item: item)
            },
            set: { newValue in editingItemID = newValue?.id }
        )
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(DS.Color.textTertiary)
            Text("No media")
                .font(DS.Text.heading)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Drag files here or use ⌘O")
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.lg)
        .accessibilityIdentifier("itemListEmptyState")
    }

    private var itemList: some View {
        List(selection: selectionBinding) {
            ForEach(document.model.items) { item in
                ItemRowView(item: item, onEdit: { editingItemID = item.id })
                .frame(height: 30)
                .contextMenu {
                    Button("Edit Media…") { editingItemID = item.id }
                        .accessibilityIdentifier("contextMenuEditMedia")
                    let revealURL = MediaReveal.revealURL(for: item.media)
                    Button("Show in Finder") {
                        if let revealURL {
                            NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                        }
                    }
                    .disabled(revealURL == nil)
                    .accessibilityIdentifier("contextMenuShowInFinder")
                    colorMenu(for: item)
                    Button("Send to grandMA2…") {
                        NotificationCenter.default.post(name: .sendToMA2Requested, object: item.id)
                    }
                    .accessibilityIdentifier("contextMenuSendToMA2")
                    Button("Export grandMA2 plugin…") {
                        NotificationCenter.default.post(name: .exportMA2PluginRequested, object: item.id)
                    }
                    .accessibilityIdentifier("contextMenuExportMA2Plugin")
                    if ltcRoutingStore.settings.isEnabled {
                        Button(item.ltcMuted ? "Unmute LTC for this clip" : "Mute LTC for this clip") {
                            CueCommands.setLTCMuted(
                                itemID: item.id,
                                muted: !item.ltcMuted,
                                document: document,
                                undoManager: undoManager
                            )
                        }
                        .accessibilityIdentifier("contextMenuToggleLTCMute")
                    }
                    Button(item.playsOriginalSourceAudio ? "Play Music Only" : "Play Original Source Audio (with timecode)") {
                        CueCommands.setPlaysOriginalSourceAudio(
                            itemID: item.id,
                            playsOriginal: !item.playsOriginalSourceAudio,
                            document: document,
                            undoManager: undoManager
                        )
                    }
                    .accessibilityIdentifier("contextMenuToggleSourceAudioMode")
                    Divider()
                    Button(role: .destructive) {
                        CueCommands.removeItem(id: item.id, document: document, undoManager: undoManager)
                    } label: {
                        Text("Remove")
                    }
                }
                .tag(Optional(item.id))
                // Fixed 30pt rows on a 32pt pitch with an inset rounded
                // selection pill (Figma 318:1238) — replaces the default List
                // variable rows + full-bleed system highlight.
                .listRowInsets(EdgeInsets(top: 1, leading: DS.Space.md, bottom: 1, trailing: DS.Space.sm))
                .listRowSeparator(.hidden)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(ItemRowFill.color(
                            isActive: item.id == document.model.activeItemID,
                            selection: DS.Color.selection
                        ))
                        .padding(.horizontal, DS.Space.xs)
                )
                // Kill the macOS blue system selection highlight so only the
                // achromatic selection pill shows (#679), and make the table
                // refuse first responder so its built-in type-select can't
                // swallow digit cue hotkeys (#750).
                .plainListSelectionHighlight(disableTypeSelect: true)
            }
            .onMove(perform: move)
            .onDelete(perform: deleteAtOffsets)
        }
        .listStyle(.plain)
        // ⌫ delete: reachable via VoiceOver/other focus, but not the plain
        // keyboard on this list — its table refuses first responder to kill
        // type-select (#750), so the surviving delete path is the row's Remove
        // context-menu item. Kept wired for any responder that can still route it.
        .onDeleteCommand { deleteSelected() }
        .scrollContentBackground(.hidden)
    }

    /// The clip's colour tag as a context-menu submenu (#782).
    ///
    /// Built from an inline `Picker`, **not** `Button` + `Label(systemImage:)`:
    /// on macOS SwiftUI silently drops the checkmark in the latter form, which
    /// cost a full debugging cycle in #752. The picker's own selection state is
    /// what draws the ✓ against the current colour.
    ///
    /// Every entry carries its name as text, so the menu is operable and
    /// announceable without colour vision; the swatch is the decoration, not
    /// the label.
    private func colorMenu(for item: MediaItem) -> some View {
        Menu("Color") {
            Picker("Color", selection: colorBinding(for: item)) {
                Text("None").tag(String?.none)
                ForEach(CuePointType.namedDefaultPalette, id: \.hex) { entry in
                    Label {
                        Text(entry.name)
                    } icon: {
                        CueColorSwatch(hex: entry.hex)
                    }
                    .tag(String?.some(entry.hex))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .accessibilityIdentifier("contextMenuMediaColor")
    }

    private func colorBinding(for item: MediaItem) -> Binding<String?> {
        Binding(
            get: { item.colorHex },
            set: { newHex in
                CueCommands.setMediaColor(
                    itemID: item.id,
                    colorHex: newHex,
                    document: document,
                    undoManager: undoManager
                )
            }
        )
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
