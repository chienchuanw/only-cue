import SwiftUI

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

    /// Per-window GO-by-type filter (#657), shared with `DocumentView` under the
    /// same key: the selected cue type's UUID string, "" = All. Drives the
    /// Show-mode picker, the current-cue highlight, and the other-type row dim.
    @SceneStorage("onlycue.showGoTypeID") var showGoTypeIDRaw = ""

    /// The single selected cue's id, when exactly one is selected — the
    /// granularity the inspector / snap / nudge / duplicate commands work at
    /// (batch versions over the whole `selection` are a follow-up leaf).
    var soleSelectedID: Cue.ID? { selection.count == 1 ? selection.first : nil }

    /// What this pane's own row taps last wrote to `selection` (#786), so the
    /// reveal-the-row `onChange` can skip those and still scroll for selections
    /// made elsewhere. Recorded as the value rather than a one-shot flag: a tap
    /// on the already-selected row writes an unchanged set, `onChange` never
    /// fires, and a flag would stay armed and swallow the next external change.
    @State private var lastRowTapSelection: Set<Cue.ID>?

    @Environment(\.undoManager) var undoManager

    /// Notes / Tempo sheets are scoped to a Cue.ID so they survive selection
    /// changes elsewhere in the UI (a sheet anchored to cue A keeps editing
    /// cue A even if the user single-clicks cue B in the list). Both kinds
    /// share a single `.sheet(item:)` binding because SwiftUI only honors
    /// one `.sheet` modifier per view — stacking two silently breaks both.
    @State var activeCueSheet: CueSheetKind?

    @AppStorage(CueListColumnWidths.numberStorageKey)
    private var numberColumnWidthRaw: Double = Double(CueListColumnWidths.numberDefault)

    @AppStorage(CueListColumnWidths.infoStorageKey)
    private var infoColumnWidthRaw: Double = Double(CueListColumnWidths.infoDefault)

    private var numberColumnWidth: CGFloat {
        CueListColumnWidths.clampNumber(CGFloat(numberColumnWidthRaw))
    }

    private var infoColumnWidth: CGFloat {
        CueListColumnWidths.clampInfo(CGFloat(infoColumnWidthRaw))
    }

    private var numberColumnWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CueListColumnWidths.clampNumber(CGFloat(numberColumnWidthRaw)) },
            set: { numberColumnWidthRaw = Double(CueListColumnWidths.clampNumber($0)) }
        )
    }

    private var infoColumnWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CueListColumnWidths.clampInfo(CGFloat(infoColumnWidthRaw)) },
            set: { infoColumnWidthRaw = Double(CueListColumnWidths.clampInfo($0)) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ActiveMediaNameHeader(name: document.model.activeItem?.resolvedName)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.lg)
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
            Text("#")
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
            Text("Info")
                .cueColumnFrame(width: infoColumnWidth, range: CueListColumnWidths.infoRange)
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(
                        width: infoColumnWidthBinding,
                        range: CueListColumnWidths.infoRange
                    )
                    .accessibilityIdentifier("cueListInfoColumnResizeHandle")
                }
        }
        // Uppercase, tracked, tertiary micro-labels — the shared section-header
        // treatment (grandMA2-style `# · NAME · INFO`, #661).
        .dsSectionHeader()
        // Reserve the same leading swatch gutter the rows carry so the columns
        // align (Figma 318:1320); trailing keeps the row edge padding.
        .padding(.leading, CueListLayout.rowLeadingGutter)
        .padding(.trailing, CueListLayout.rowHorizontalPadding)
        // Mirror the inset macOS's List adds to the rows below — the header is
        // outside the List, so without this its columns sit left of the values
        // (#661 follow-up; guarded by CueListColumnAlignmentUITests).
        .padding(.horizontal, CueListLayout.listRowHorizontalInset)
        .padding(.vertical, DS.Space.sm)
        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
        .disabled(isReadOnly)
    }

    private var cueList: some View {
        VStack(spacing: 0) {
            CueListSectionHeader(count: cues.count)
            headerRow
            Divider()
            scrollableList
            Divider()
            // Show mode (read-only) pins a "Read-only — Show Mode" lock footer
            // (Figma 318:1608); editable modes keep the Manage Types… footer.
            if isReadOnly {
                ShowGoTypePicker(types: document.model.cuePointTypes, selectionRaw: $showGoTypeIDRaw)
                Divider()
                ShowModeFooter()
            } else {
                CueListFooter()
            }
        }
    }

    private var scrollableList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(cues, id: \.id) { cue in
                    cueRow(for: cue)
                        .opacity(rowOpacity(for: cue))
                        // Expose the playhead's current cue to VoiceOver, matching
                        // the lyrics pane's current-line trait (#671).
                        .accessibilityAddTraits(cue.id == currentCueID ? .isSelected : [])
                        .contextMenu { cueContextMenu(for: cue) }
                        .tag(cue.id)
                        .listRowBackground(rowBackground(for: cue))
                        // Kill the macOS blue system selection highlight so only
                        // the cue-type tint row background shows (#679).
                        .plainListSelectionHighlight()
                }
                .onDelete(perform: isReadOnly ? nil : deleteAtOffsets)
            }
            .onDeleteCommand { if !isReadOnly { deleteSelected() } }
            // Selecting a cue deliberately does not seek (#786) — only the
            // row's colour stripe does. Do not re-add a seek here.
            //
            // The scroll does survive, because the selection has sources
            // outside this pane — a timeline marker tap (`DocumentView`'s
            // `onSelectCue`) and pause-at-each-cue — and those need the row
            // revealed. A tap on a row is the one case that must not scroll:
            // that row is already under the pointer, and centring it would
            // yank the list out from under the caret that just opened.
            .onChange(of: selection) { _, newValue in
                guard newValue != lastRowTapSelection else {
                    lastRowTapSelection = nil
                    return
                }
                guard let id = soleSelectedID else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            // Keep the playhead's current cue visible, but only while playing —
            // scrolling during editing would yank the list (#671). Fires once
            // per cue-section crossing (currentCueID changes), not per frame.
            .onChange(of: currentCueID) { _, id in
                guard engine.isPlaying, let id else { return }
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
            numberColumnWidth: numberColumnWidth,
            infoColumnWidth: infoColumnWidth,
            onRename: { newName in
                CueCommands.rename(cueId: cue.id, to: newName, document: document, undoManager: undoManager)
            },
            onCommitNumber: { newNumber in
                CueCommands.setCueNumber(cueId: cue.id, to: newNumber, document: document, undoManager: undoManager)
            },
            onCommitNotes: { newNotes in
                CueCommands.setNotes(cueId: cue.id, to: newNotes, document: document, undoManager: undoManager)
            },
            // Same shape as the timeline's marker taps (`DocumentView`'s
            // `onSelectCue` / `onToggleCue`), over the same selection set.
            // Both record what they set so the scroll `onChange` can recognise
            // its own pane's clicks and leave the list where it is.
            onSelect: {
                lastRowTapSelection = [cue.id]
                selection = [cue.id]
            },
            onExtendSelection: {
                var updated = selection
                updated.formSymmetricDifference([cue.id])
                lastRowTapSelection = updated
                selection = updated
            },
            onSeek: { Task { await engine.seek(to: cue.time) } },
            isReadOnly: isReadOnly
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
