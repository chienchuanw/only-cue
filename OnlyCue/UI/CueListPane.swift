import SwiftUI

enum CueListLayout {
    static let rowHorizontalSpacing: CGFloat = 8
    static let rowTintOpacity: Double = 0.18
}

// swiftlint:disable:next type_body_length
struct CueListPane: View {

    static let headerAccessibilityIdentifier = "cueListHeader"

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @Binding var selection: Set<Cue.ID>

    /// The single selected cue's id, when exactly one is selected — the
    /// granularity the inspector / snap / nudge / duplicate commands work at
    /// (batch versions over the whole `selection` are a follow-up leaf).
    var soleSelectedID: Cue.ID? { selection.count == 1 ? selection.first : nil }

    @Environment(\.undoManager) var undoManager

    /// Notes / Tempo sheets are scoped to a Cue.ID so they survive selection
    /// changes elsewhere in the UI (a sheet anchored to cue A keeps editing
    /// cue A even if the user single-clicks cue B in the list).
    @State var notesEditingID: Cue.ID?
    @State var tempoEditingID: Cue.ID?

    @AppStorage(CueListColumnWidths.timeStorageKey)
    private var timeColumnWidthRaw: Double = Double(CueListColumnWidths.timeDefault)

    @AppStorage(CueListColumnWidths.numberStorageKey)
    private var numberColumnWidthRaw: Double = Double(CueListColumnWidths.numberDefault)

    @AppStorage(CueListColumnWidths.fadeStorageKey)
    private var fadeColumnWidthRaw: Double = Double(CueListColumnWidths.fadeDefault)

    private var timeColumnWidth: CGFloat {
        CueListColumnWidths.clampTime(CGFloat(timeColumnWidthRaw))
    }

    private var numberColumnWidth: CGFloat {
        CueListColumnWidths.clampNumber(CGFloat(numberColumnWidthRaw))
    }

    private var fadeColumnWidth: CGFloat {
        CueListColumnWidths.clampFade(CGFloat(fadeColumnWidthRaw))
    }

    private var timeColumnWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CueListColumnWidths.clampTime(CGFloat(timeColumnWidthRaw)) },
            set: { timeColumnWidthRaw = Double(CueListColumnWidths.clampTime($0)) }
        )
    }

    private var numberColumnWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CueListColumnWidths.clampNumber(CGFloat(numberColumnWidthRaw)) },
            set: { numberColumnWidthRaw = Double(CueListColumnWidths.clampNumber($0)) }
        )
    }

    private var fadeColumnWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CueListColumnWidths.clampFade(CGFloat(fadeColumnWidthRaw)) },
            set: { fadeColumnWidthRaw = Double(CueListColumnWidths.clampFade($0)) }
        )
    }

    private var selectedCue: Cue? {
        guard let id = soleSelectedID else { return nil }
        return cues.first(where: { $0.id == id })
    }

    func rowTint(for cue: Cue) -> Color {
        guard let hex = document.model.colorHex(for: cue),
              let base = Color(hex: hex) else {
            return Color.clear
        }
        return base.opacity(CueListLayout.rowTintOpacity)
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

            CueInspectorView(document: document, engine: engine, cue: selectedCue)
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
        .onReceive(NotificationCenter.default.publisher(for: .snapSelectedCuesToBeat)) { _ in
            snapSelectedToGrid(.beat)
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapSelectedCuesToBar)) { _ in
            snapSelectedToGrid(.bar)
        }
        .sheet(item: notesEditingBinding) { editing in
            CueNotesSheet(
                cueLabel: cueSheetLabel(for: editing.cue),
                initialNotes: editing.cue.notes,
                onSave: { newNotes in
                    CueCommands.setNotes(
                        cueId: editing.cue.id,
                        to: newNotes,
                        document: document,
                        undoManager: undoManager
                    )
                    notesEditingID = nil
                },
                onCancel: { notesEditingID = nil }
            )
        }
        .sheet(item: tempoEditingBinding) { editing in
            tempoSheet(for: editing.cue)
        }
    }

    @ViewBuilder
    private func tempoSheet(for cue: Cue) -> some View {
        CueTempoSheet(
            cueLabel: cueSheetLabel(for: cue),
            initialBPM: cue.bpm,
            initialBeatsPerBar: cue.beatsPerBar,
            onDetect: { beats in
                await runTempoDetect(for: cue, beatsPerBar: beats)
            },
            onSave: { bpm, beats in
                if let itemID = itemID(owning: cue.id) {
                    CueCommands.setCueTempo(
                        cueID: cue.id,
                        bpm: bpm,
                        beatsPerBar: beats,
                        item: itemID,
                        document: document,
                        undoManager: undoManager
                    )
                }
                tempoEditingID = nil
            },
            onCancel: { tempoEditingID = nil }
        )
    }

    var cues: [Cue] { document.model.activeItem?.cues ?? [] }

    private static let nudgeStep: TimeInterval = 1.0 / 30.0

    private var activeItemDuration: TimeInterval { document.model.activeItem?.media.duration ?? 0 }

    private var activeTempoGrid: DerivedTempoGrid {
        guard let item = document.model.activeItem else { return DerivedTempoGrid(segments: []) }
        return DerivedTempoGrid.from(cues: item.cues)
    }

    private func snapSelectedToGrid(_ resolution: CueCommands.GridResolution) {
        let grid = activeTempoGrid
        let duration = activeItemDuration
        switch resolution {
        case .beat:
            CueCommands.snapCues(selection, toBeatIn: grid, itemDuration: duration, document: document, undoManager: undoManager)
        case .bar:
            CueCommands.snapCues(selection, toBarIn: grid, itemDuration: duration, document: document, undoManager: undoManager)
        }
    }

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

    private var headerRow: some View {
        // Keep the header's layout identical to CueRowView so the columns
        // line up exactly: same HStack spacing, same fixed Time/Number
        // widths, same flexible Name. The resize handles are mounted as
        // non-layout-participating trailing overlays so they do not
        // perturb the intrinsic width of the header (#269).
        //
        // The handles intentionally sit fully inside the parent text frame
        // (no .offset escaping the parent): an overlay whose hit-test
        // region extends outside its parent confuses NSHostingView min-size
        // reporting and feeds the NSSplitView constraint-update loop
        // during outer-divider tracking (#271).
        HStack(spacing: CueListLayout.rowHorizontalSpacing) {
            Text("Time")
                .frame(width: timeColumnWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(
                        width: timeColumnWidthBinding,
                        range: CueListColumnWidths.timeRange
                    )
                    .accessibilityIdentifier("cueListTimeColumnResizeHandle")
                }
            Text("Cue #")
                .frame(width: numberColumnWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(
                        width: numberColumnWidthBinding,
                        range: CueListColumnWidths.numberRange
                    )
                    .accessibilityIdentifier("cueListNumberColumnResizeHandle")
                }
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Fade")
                .frame(width: fadeColumnWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(
                        width: fadeColumnWidthBinding,
                        range: CueListColumnWidths.fadeRange
                    )
                    .accessibilityIdentifier("cueListFadeColumnResizeHandle")
                }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
    }

    private var cueList: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            scrollableList
        }
    }

    private var scrollableList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(cues, id: \.id) { cue in
                    cueRow(for: cue)
                        .tag(cue.id)
                        .listRowBackground(rowTint(for: cue))
                        .contextMenu { cueRowContextMenu(for: cue) }
                }
                .onDelete(perform: deleteAtOffsets)
            }
            .onDeleteCommand { deleteSelected() }
            .onChange(of: selection) { _, _ in
                guard
                    let id = soleSelectedID,
                    let cue = cues.first(where: { $0.id == id })
                else { return }
                Task { await engine.seek(to: cue.time) }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func cueRow(for cue: Cue) -> CueRowView {
        CueRowView(
            cue: cue,
            resolvedColorHex: document.model.colorHex(for: cue),
            timeColumnWidth: timeColumnWidth,
            numberColumnWidth: numberColumnWidth,
            fadeColumnWidth: fadeColumnWidth,
            onRename: { newName in
                CueCommands.rename(cueId: cue.id, to: newName, document: document, undoManager: undoManager)
            },
            onCommitNumber: { newNumber in
                CueCommands.setCueNumber(cueId: cue.id, to: newNumber, document: document, undoManager: undoManager)
            },
            onCommitFade: { newFade in
                CueCommands.setFadeTime(cueId: cue.id, to: newFade, document: document, undoManager: undoManager)
            }
        )
    }

    func deleteAtOffsets(_ offsets: IndexSet) {
        for index in offsets {
            guard cues.indices.contains(index) else { continue }
            let cue = cues[index]
            CueCommands.delete(cueId: cue.id, document: document, undoManager: undoManager)
        }
    }

    func deleteSelected() {
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
