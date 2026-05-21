import SwiftUI

enum CueListLayout {
    static let rowHorizontalSpacing: CGFloat = 8
    /// Horizontal edge padding on the header row. Shared with
    /// `headerHorizontalChrome` so the #297 width floor can never silently
    /// diverge from the padding actually rendered.
    static let rowHorizontalPadding: CGFloat = 8
    static let rowTintOpacity: Double = 0.18

    /// Non-column horizontal cost of the header row: the 3 inter-column gaps
    /// (`rowHorizontalSpacing` each) plus `rowHorizontalPadding` on both
    /// edges. The Name column is flexible with no enforced intrinsic
    /// minimum, so it compresses to ~0 and contributes nothing to the floor.
    static let headerHorizontalChrome: CGFloat =
        3 * rowHorizontalSpacing + 2 * rowHorizontalPadding

    /// The cue-list header's guaranteed-compressible minimum width — the
    /// value the outer `NSSplitView` sees as the pane's hard floor. Issue
    /// #297: this must never exceed `CueListInspectorMetrics.minWidth`, or
    /// the splitter cannot reach the 240 column minimum without the content
    /// demanding more and feeding the constraint-update loop. `CueRowView`
    /// rows carry a leading color swatch (~14pt of leading chrome) but stay
    /// inside the same 40pt slack, so the header is the binding floor.
    static var headerMinimumWidth: CGFloat {
        CueListColumnWidths.timeRange.lowerBound
            + CueListColumnWidths.numberRange.lowerBound
            + CueListColumnWidths.fadeRange.lowerBound
            + headerHorizontalChrome
    }
}

// swiftlint:disable:next type_body_length
struct CueListPane: View {

    static let headerAccessibilityIdentifier = "cueListHeader"

    /// The pane's minimum width. Defers to the shared inspector-column
    /// metric so it can never diverge from `.inspectorColumnWidth` and
    /// reintroduce the issue #297 constraint loop.
    static let minPaneWidth: CGFloat = CueListInspectorMetrics.minWidth

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @Binding var selection: Set<Cue.ID>
    /// When true (Show mode) the cue list is read-only: row fields, the
    /// context menu, delete, and column resize are all disabled.
    var isReadOnly: Bool = false

    /// The single selected cue's id, when exactly one is selected — the
    /// granularity the inspector / snap / nudge / duplicate commands work at
    /// (batch versions over the whole `selection` are a follow-up leaf).
    var soleSelectedID: Cue.ID? { selection.count == 1 ? selection.first : nil }

    @Environment(\.undoManager) var undoManager

    /// Notes / Tempo sheets are scoped to a Cue.ID so they survive selection
    /// changes elsewhere in the UI (a sheet anchored to cue A keeps editing
    /// cue A even if the user single-clicks cue B in the list). Both kinds
    /// share a single `.sheet(item:)` binding because SwiftUI only honors
    /// one `.sheet` modifier per view — stacking two silently breaks both.
    @State var activeCueSheet: CueSheetKind?

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

    func rowTint(for cue: Cue) -> Color {
        guard let hex = document.model.colorHex(for: cue),
              let base = Color(hex: hex) else {
            return Color.clear
        }
        return base.opacity(CueListLayout.rowTintOpacity)
    }

    /// The cue currently "active" at the playhead — emphasized in Show mode.
    private var currentCueID: Cue.ID? {
        document.model.activeItem?.activeCue(at: engine.currentTime)?.id
    }

    /// A row's background — the cue's type tint, or an accent highlight for the
    /// cue currently playing when the list is read-only (Show mode).
    private func rowBackground(for cue: Cue) -> Color {
        if isReadOnly, cue.id == currentCueID {
            return Color.accentColor.opacity(0.25)
        }
        return rowTint(for: cue)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayheadClockHeader(engine: engine)
            Group {
                if cues.isEmpty {
                    emptyState
                } else {
                    cueList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.panel)
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
        .sheet(item: $activeCueSheet) { sheet in
            cueSheetContent(for: sheet)
        }
    }

    var cues: [Cue] { document.model.activeItem?.cues ?? [] }

    private static let nudgeStep: TimeInterval = 1.0 / 30.0

    private var activeItemDuration: TimeInterval { document.model.activeItem?.media.duration ?? 0 }

    private var activeTempoGrid: DerivedTempoGrid {
        guard let item = document.model.activeItem else { return DerivedTempoGrid(segments: []) }
        return DerivedTempoGrid.from(cues: item.cues)
    }

    private func snapSelectedToGrid(_ resolution: CueCommands.GridResolution) {
        guard !isReadOnly else { return }
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
        guard !isReadOnly, let id = soleSelectedID else { return }
        CueCommands.duplicateAtPlayhead(
            cueId: id,
            time: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }

    private func snapSelectedToPlayhead() {
        guard !isReadOnly else { return }
        CueCommands.snapCues(selection, to: engine.currentTime, document: document, undoManager: undoManager)
    }

    private func nudgeSelected(by step: TimeInterval) {
        guard !isReadOnly else { return }
        CueCommands.nudgeCues(selection, by: step, document: document, undoManager: undoManager)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(DS.Color.textTertiary)
            Text("No cues yet")
                .font(DS.Text.heading)
                .foregroundStyle(DS.Color.textPrimary)
            Text(document.model.activeItem == nil
                 ? "Import a media file to start adding cues."
                 : "Press M to add a cue at the playhead.")
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cueListEmptyStateMessage")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.lg)
        // `.contain` keeps the message Text individually queryable — without it
        // the icon + text VStack collapses into one merged AX element.
        .accessibilityElement(children: .contain)
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
                .cueColumnFrame(width: timeColumnWidth, range: CueListColumnWidths.timeRange)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(
                        width: timeColumnWidthBinding,
                        range: CueListColumnWidths.timeRange
                    )
                    .accessibilityIdentifier("cueListTimeColumnResizeHandle")
                }
            Text("Cue #")
                .cueColumnFrame(width: numberColumnWidth, range: CueListColumnWidths.numberRange)
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
                .cueColumnFrame(width: fadeColumnWidth, range: CueListColumnWidths.fadeRange)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(
                        width: fadeColumnWidthBinding,
                        range: CueListColumnWidths.fadeRange
                    )
                    .accessibilityIdentifier("cueListFadeColumnResizeHandle")
                }
        }
        .font(DS.Text.label)
        .foregroundStyle(DS.Color.textSecondary)
        .padding(.horizontal, CueListLayout.rowHorizontalPadding)
        .padding(.vertical, DS.Space.sm)
        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
        .disabled(isReadOnly)
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
                        .contextMenu { cueContextMenu(for: cue) }
                        .tag(cue.id)
                        .listRowBackground(rowBackground(for: cue))
                }
                .onDelete(perform: isReadOnly ? nil : deleteAtOffsets)
            }
            .onDeleteCommand { if !isReadOnly { deleteSelected() } }
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
            .scrollContentBackground(.hidden)
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
            },
            isReadOnly: isReadOnly
        )
    }

    /// The per-row right-click menu — empty (no menu) when the list is
    /// read-only (Show mode).
    @ViewBuilder
    private func cueContextMenu(for cue: Cue) -> some View {
        if !isReadOnly {
            Button("Edit Notes…") { activeCueSheet = .notes(cue.id) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .accessibilityIdentifier("cueRowContextEditNotes")
            Button("Tempo…") { activeCueSheet = .tempo(cue.id) }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .accessibilityIdentifier("cueRowContextTempo")
            Menu("Change Type") {
                ForEach(document.model.cuePointTypes) { type in
                    Button {
                        guard type.id != cue.typeID else { return }
                        CueCommands.setType(
                            cueId: cue.id,
                            to: type.id,
                            document: document,
                            undoManager: undoManager
                        )
                    } label: {
                        Label {
                            Text(type.name)
                        } icon: {
                            if type.id == cue.typeID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("cueRowContextChangeType-\(type.id)")
                }
            }
            .accessibilityIdentifier("cueRowContextChangeType")
        }
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
