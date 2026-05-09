import SwiftUI

struct CueListPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @Binding var selection: Cue.ID?

    @Environment(\.undoManager) private var undoManager

    private var cues: [Cue] { document.model.activeItem?.cues ?? [] }

    private var selectedCue: Cue? {
        guard let id = selection else { return nil }
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
        guard let id = selection else { return }
        CueCommands.duplicateAtPlayhead(
            cueId: id,
            time: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }

    private func snapSelectedToPlayhead() {
        guard let id = selection else { return }
        CueCommands.retime(
            cueId: id,
            to: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }

    private func nudgeSelected(by step: TimeInterval) {
        guard
            let id = selection,
            let cue = cues.first(where: { $0.id == id })
        else { return }
        CueCommands.retime(
            cueId: id,
            to: cue.time + step,
            document: document,
            undoManager: undoManager
        )
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
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
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
            .onChange(of: selection) { _, newValue in
                guard
                    let id = newValue,
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

extension Notification.Name {
    static let snapSelectedCueToPlayhead = Notification.Name("OnlyCue.snapSelectedCueToPlayhead")
    static let nudgeSelectedCueBack = Notification.Name("OnlyCue.nudgeSelectedCueBack")
    static let nudgeSelectedCueForward = Notification.Name("OnlyCue.nudgeSelectedCueForward")
    static let duplicateSelectedCueAtPlayhead = Notification.Name("OnlyCue.duplicateSelectedCueAtPlayhead")
}
