import SwiftUI

struct CueListPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @Binding var selection: Set<Cue.ID>

    /// The single selected cue's id, when exactly one is selected — the
    /// granularity the inspector / snap / nudge / duplicate commands work at
    /// (batch versions over the whole `selection` are a follow-up leaf).
    private var soleSelectedID: Cue.ID? { selection.count == 1 ? selection.first : nil }

    @Environment(\.undoManager) private var undoManager
    @State private var searchQuery: String = ""

    private var cues: [Cue] { document.model.activeItem?.cues ?? [] }
    private var visibleCues: [Cue] { Self.filtered(cues, by: searchQuery) }

    /// Pure filter helper — case-insensitive localized contains on name OR notes.
    /// Whitespace-only queries return the unfiltered list (matches macOS spotlight
    /// behavior). Selection state is intentionally independent of this filter:
    /// callers continue to look up `selectedCue` against the full `cues` array,
    /// so a cue can stay selected (and emphasized on the waveform) while filtered
    /// out of the rendered list.
    static func filtered(_ cues: [Cue], by query: String) -> [Cue] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cues }
        return cues.filter { cue in
            cue.name.localizedCaseInsensitiveContains(trimmed) ||
            cue.notes.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var selectedCue: Cue? {
        guard let id = soleSelectedID else { return nil }
        return cues.first(where: { $0.id == id })
    }

    var body: some View {
        VSplitView {
            Group {
                if cues.isEmpty {
                    emptyState
                } else {
                    cueList
                }
            }
            .frame(minHeight: 120)

            CueInspectorView(document: document, cue: selectedCue)
                .frame(minHeight: 180)
        }
        .frame(minWidth: 240)
        .accessibilityIdentifier("cueListPane")
        .onReceive(NotificationCenter.default.publisher(for: .snapSelectedCueToPlayhead)) { _ in
            snapSelectedToPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nudgeSelectedCueBack)) { _ in
            nudgeSelected(by: -Self.nudgeStep)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nudgeSelectedCueForward)) { _ in
            nudgeSelected(by: Self.nudgeStep)
        }
        .onReceive(NotificationCenter.default.publisher(for: .duplicateSelectedCueAtPlayhead)) { _ in
            duplicateSelectedAtPlayhead()
        }
    }

    private static let nudgeStep: TimeInterval = 1.0 / 30.0

    private func duplicateSelectedAtPlayhead() {
        guard let id = soleSelectedID else { return }
        CueCommands.duplicateAtPlayhead(
            cueId: id,
            time: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }

    private func snapSelectedToPlayhead() {
        CueCommands.snapCues(selection, to: engine.currentTime, document: document, undoManager: undoManager)
    }

    private func nudgeSelected(by step: TimeInterval) {
        CueCommands.nudgeCues(selection, by: step, document: document, undoManager: undoManager)
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

    private var searchField: some View {
        TextField("Search cues", text: $searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .accessibilityIdentifier("cueListSearchField")
    }

    private var cueList: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            scrollableList
        }
    }

    private var scrollableList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(Array(visibleCues.enumerated()), id: \.element.id) { index, cue in
                    CueRowView(
                        index: index + 1,
                        cue: cue,
                        resolvedColorHex: document.model.colorHex(for: cue),
                        onRename: { newName in
                            CueCommands.rename(cueId: cue.id, to: newName, document: document, undoManager: undoManager)
                        }
                    )
                    .tag(cue.id)
                }
                .onDelete(perform: deleteAtOffsets)
            }
            .onDeleteCommand { deleteSelected() }
            .onChange(of: selection) { _, _ in
                // Seek/scroll only on a single-cue selection — a multi-select
                // shouldn't yank the playhead or re-center the list.
                guard
                    let id = soleSelectedID,
                    let cue = cues.first(where: { $0.id == id })
                else { return }
                Task { await engine.seek(to: cue.time) }
                // Centered scroll-to-selection brings offscreen rows into view when
                // selection is driven externally (marker click, snap/nudge). For
                // already-visible rows the re-center is a mild flicker — acceptable
                // per the issue body's UX trade-off analysis.
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        // ForEach iterates `visibleCues`, so swipe-to-delete offsets index into
        // the filtered list — resolve via `visibleCues` to get the right cue ID.
        let target = visibleCues
        for index in offsets {
            guard target.indices.contains(index) else { continue }
            let cue = target[index]
            CueCommands.delete(cueId: cue.id, document: document, undoManager: undoManager)
        }
    }

    private func deleteSelected() {
        guard !selection.isEmpty else { return }
        for id in selection {
            CueCommands.delete(cueId: id, document: document, undoManager: undoManager)
        }
        selection = []
    }
}

extension Notification.Name {
    static let snapSelectedCueToPlayhead = Notification.Name("OnlyCue.snapSelectedCueToPlayhead")
    static let nudgeSelectedCueBack = Notification.Name("OnlyCue.nudgeSelectedCueBack")
    static let nudgeSelectedCueForward = Notification.Name("OnlyCue.nudgeSelectedCueForward")
    static let duplicateSelectedCueAtPlayhead = Notification.Name("OnlyCue.duplicateSelectedCueAtPlayhead")
}
