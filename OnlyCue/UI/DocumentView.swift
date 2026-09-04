import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    /// Directory of the opened `.cuelist` on disk (from the DocumentGroup's
    /// `FileDocumentConfiguration.fileURL`), used to auto-attach bundled media in
    /// a sibling `media/` folder (#641). nil for a never-saved document.
    var documentDirectory: URL?
    @State var engine = PlayerEngine()
    @State private var showImporter = false
    /// The id of the media item awaiting a relink file selection (#577).
    @State var relinkTarget: MediaItem.ID?
    @State var pendingAlert: DocumentAlert?
    @State var seekTask: Task<Void, Never>?
    @State private var showOverlayAppearance = false
    /// Native `NavigationSplitView` sidebar visibility. Per-window `@State`
    /// (each document window owns its own), bound below so ⌃⌘S / an applied
    /// preset can hide or show the sidebar. `internal`, not `private`: the
    /// capture/restore `onChange`es live in DocumentView+Workspace.swift to keep
    /// this file under SwiftLint's file_length cap.
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @State var cueSelection: Set<Cue.ID> = []
    /// The unplaced-lyric-queue cursor — UI working state for placement.
    @State private var lyricsCursor = LyricsAuthoringCursor()
    @AppStorage(FirstLaunchFlag.key) var didShowFirstLaunch = false
    @AppStorage(NotesOverlayPreferences.storageKey) var overlayPrefsData = NotesOverlayPreferences.defaultEncoded
    @AppStorage("pauseAtEachCue") var pauseAtEachCue = false
    /// The editor mode — per-window working state, restored across relaunch.
    @SceneStorage("onlycue.editorMode") private var editorModeRaw = EditorMode.cue.rawValue
    @SceneStorage("onlycue.showGoTypeID") var showGoTypeIDRaw = ""
    @State var miniController = MiniPlayerController()
    @State var miniContext = MiniPlayerContext()
    /// TRUE when THIS document's own main window currently holds key. (Named for
    /// its true meaning — it does not track the Mini Player panel; the panel is
    /// non-activating and never becomes key.) Published by `FrontmostWindowGate`
    /// and used to scope broadcast notifications to the frontmost document.
    @State var isMainWindowKey = false
    @AppStorage("onlycue.miniPlayerVisible") var miniPlayerVisible = false
    @State var miniKeyMonitor: Any?
    @State var isMainWindowCollapsed = false
    @State var documentWindow: NSWindow?
    @State var seekBox = SeekTaskBox()
    /// The window's live pane arrangement per editor mode (`@SceneStorage` so two
    /// open documents keep independent arrangements; restored across relaunch).
    /// `internal` (not `private`): read/written by DocumentView+Workspace.swift.
    @SceneStorage("onlycue.workspaceLayout") var liveLayoutData = ""
    /// -1 means "no pending apply". A sentinel rather than `CGFloat?` because
    /// `@State` of an optional here reads worse at every call site than one
    /// impossible width does. Accessed by the extension in
    /// DocumentView+Workspace.swift — `private` can't reach across files.
    @State var pendingSidebarWidthValue: CGFloat = -1
    /// The window's content width, measured live so preset application can
    /// clamp against what is actually there (spec decision 8).
    /// `internal`, not `private`: written by the background modifier in
    /// DocumentView+Workspace.swift.
    @State var availableWindowWidth: CGFloat = 0
    /// Shared waveform zoom/scroll — waveform + LTC strip stay collinear (#669).
    /// `internal`, not `private`: used by the extension in DocumentView+LTCStrip.swift.
    @State var waveformZoom = WaveformZoomController()
    @ObservedObject private var keymapStore = KeymapStore.shared
    /// Drives the main-view LTC strip's visibility — it appears whenever LTC
    /// routing is enabled. Observing the singleton here means flipping the
    /// switch in Preferences updates the strip in real time.
    @ObservedObject var ltcRoutingStore = LTCRoutingStore.shared
    @Environment(\.undoManager) var undoManager
    /// True while an inline cue field (name/number/fade) is being edited, so the
    /// bare arrow-key transport/step shortcuts yield to the text field (#573).
    @FocusedValue(\.editingCueField) private var editingCueField

    /// Whether an inline cue field is currently being edited.
    var isEditingCueField: Bool { InlineEditGate.isEditing(editingCueField) }

    func shortcut(_ action: KeymapAction) -> KeyboardShortcut {
        keymapStore.keymap.chord(for: action).keyboardShortcut
            ?? Keymap.default.chord(for: action).keyboardShortcut
            ?? KeyboardShortcut(KeyEquivalent("/"), modifiers: .command)
    }

    var editorMode: EditorMode { EditorMode(rawValue: editorModeRaw) ?? .cue }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ItemListPane(document: document, onDropURLs: importURLs)
                .navigationSplitViewColumnWidth(
                    min: SidebarMetrics.minWidth,
                    ideal: SidebarMetrics.idealWidth,
                    max: SidebarMetrics.maxWidth)
                .sidebarWidthBridge(targetWidth: pendingSidebarWidth) { measured in
                    if let pw = pendingSidebarWidth, abs(measured - pw) < 1 { pendingSidebarWidth = nil }
                    updateLiveLayout { $0.sidebarWidth = measured }
                }
        } detail: {
            // Plain HStack, NOT `.inspector` or `HSplitView` (#617): any
            // NSSplitView-backed split inside the detail column double-counts
            // the sidebar into the window's minimum width (~+249pt) and holds
            // the inspector at its ideal/max instead of its minimum, pinning
            // the populated window at 1416pt — past the 1280pt design width.
            // Verified empirically by bisecting all pane content to
            // `Color.clear`. The divider below restores the drag that comment
            // named as the only casualty, WITHOUT restoring the split view:
            // the gesture writes a width into scene storage, which feeds the
            // same frame contract that was already here (#714).
            HStack(spacing: 0) {
                mainPane
                if !currentPaneLayout.isInspectorCollapsed {
                    InspectorDivider(width: inspectorWidthBinding)
                    ModeAwareInspector(
                        document: document,
                        engine: engine,
                        editorMode: editorMode,
                        cueSelection: $cueSelection,
                        lyricsCursor: $lyricsCursor
                    )
                    .frame(width: currentPaneLayout.inspectorWidth)
                }
            }
            .animation(DS.Motion.quick, value: currentPaneLayout.isInspectorCollapsed)
        }
        // Figma 318:1236: the titlebar subtitle is the editor mode, not the
        // active media item name (the active clip is already shown in the
        // sidebar / preview).
        .navigationSubtitle("\(editorMode.title) Mode")
        .sheet(isPresented: firstLaunchBinding) {
            FirstLaunchSheet { didShowFirstLaunch = true }
        }
        .task(id: document.model.activeItemID) { await reloadActive() }
        .stripedTimecodeReader(item: document.model.activeItem, document: document)
        .onChange(of: document.model.activeItemID) { _, _ in
            // Clear stale selection on item switch — the new item's cues won't
            // contain the previous item's selected Cue.ID, so leaving it set
            // produces a silent inspector-empty state with no visual indication.
            cueSelection = []
        }
        .onChange(of: engine.currentTime) { oldValue, newValue in
            handlePauseAtEachCue(from: oldValue, to: newValue)
        }
        .resignFirstResponderOnOutsideClick()
        .onReceive(NotificationCenter.default.publisher(for: .editNotesOverlayAppearance)) { _ in
            showOverlayAppearance = true
        }
        .sheet(isPresented: $showOverlayAppearance) {
            NotesOverlayPreferencesSheet(prefs: overlayPrefsBinding)
        }
        .manageTypesSheet(document: document)
        .timecodeSettingsSheet(document: document)
        .onReceive(NotificationCenter.default.publisher(for: .editorModeChangeRequested)) { note in
            if let mode = note.object as? EditorMode { editorModeRaw = mode.rawValue }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setPlaybackModeRequested)) { note in
            if let mode = note.object as? PlaybackMode {
                CueCommands.setPlaybackMode(mode, document: document, undoManager: undoManager)
            }
        }
        .focusedSceneValue(\.currentPlaybackMode, document.model.playbackMode)
        .onReceive(engine.mediaDidReachEnd) { _ in
            handleMediaDidReachEnd()
        }
        .exportSheet(model: document.model, pendingErrorMessage: pendingAlertMessageBinding)
        .ma2PushSheet(document: document, undoManager: undoManager)
        .ma2PluginExport(document: document, undoManager: undoManager)
        .oscServerHost(engine: engine, document: document, undoManager: undoManager, editorMode: editorMode, showGoTypeID: showGoTypeID)
        .midiInputHost(engine: engine, document: document, undoManager: undoManager, editorMode: editorMode, showGoTypeID: showGoTypeID)
        .ltcOutput(engine: engine, document: document)
        .mtcOutput(engine: engine, document: document)
        .environment(\.projectFramerate, document.model.timecodeSettings.framerate)
        .workspaceHosted(for: self)
        .sidebarVisibilitySync(for: self)
        .miniPlayerHosted(for: self)
    }

    private var mainPane: some View {
        let activeItem = document.model.activeItem
        return VStack(spacing: 12) {
            if activeItem == nil {
                DocumentEmptyState(onImport: { showImporter = true })
                    .padding()
            } else {
                PreviewPane(
                    document: document,
                    engine: engine,
                    selectedCueIDs: cueSelection,
                    onSelectCue: { cueSelection = [$0] },
                    onToggleCue: { cueSelection.formSymmetricDifference([$0]) },
                    editorMode: editorMode,
                    setEditorMode: { editorModeRaw = $0.rawValue },
                    lyricsCursor: $lyricsCursor,
                    waveformZoom: waveformZoom,
                    activeCueTypeID: showGoTypeID
                )

                // The LTC strip + transport are the bottom control group and sit
                // flush together (Figma 318:1308/318:1309 stack contiguously);
                // the outer VStack's gap stays above the group, separating it
                // from the waveform well rather than from the transport.
                VStack(spacing: 0) {
                    ltcStripIfEnabled(activeItem)

                    TransportControls(
                        engine: engine,
                        cues: activeItem?.cues ?? [],
                        mediaDuration: activeItem?.media.duration ?? 0,
                        timecodeSettings: document.model.timecodeSettings,
                        activeItem: activeItem,
                        playbackMode: document.model.playbackMode,
                        onStepPrevCue: { stepPlayhead(.previous) },
                        onStepNextCue: { stepPlayhead(.next) },
                        onStepPrevSong: { stepSong(.previous) },
                        onStepNextSong: { stepSong(.next) },
                        canStepPrevSong: canStepPrevSong,
                        canStepNextSong: canStepNextSong,
                        activeCueTypeID: showGoTypeID,
                        onGo: editorMode == .show ? { performGo() } : nil
                    )
                    // Pin the transport to its natural height: its internal
                    // full-height divider (.frame(maxHeight: .infinity)) would
                    // otherwise make the whole bar greedy and split the column
                    // with the preview, leaving a large empty box (Figma 318:1309
                    // is a thin ~50pt row). fixedSize lets PreviewPane fill.
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Invisible keyboard-shortcut hosts live in `.background`, NOT the VStack
        // — as 0×0 children they still earned the VStack's 12pt spacing, which
        // stacked up and pushed the transport ~60pt off the bottom (#514).
        .background {
            ZStack {
                transportShortcuts
                digitShortcuts
                lyricTapAlongShortcut
                PlayheadStepShortcuts(
                    onStepPrev: { stepPlayhead(.previous) },
                    onStepNext: { stepPlayhead(.next) },
                    isEnabled: InlineEditGate.stepShortcutsEnabled(
                        hasActiveItem: document.model.activeItem != nil,
                        isEditingCueField: isEditingCueField
                    ),
                    shortcutFor: shortcut
                )
                PlaybackRateShortcuts(
                    engine: engine,
                    ltcEnabled: ltcRoutingStore.settings.isEnabled,
                    shortcutFor: shortcut
                )
                ShowGoShortcut(
                    onGo: { performGo() },
                    isEnabled: editorMode == .show && document.model.activeItem != nil
                )
                DocumentWindowAccessor(
                    onResolve: { documentWindow = $0 },
                    shouldCollapseOnClose: {
                        MiniPlayerCollapse.onMainWindowClose(miniVisible: miniController.isVisible) == .collapseToMini
                    },
                    onCollapse: { collapseMainWindow() }
                )
                .frame(width: 0, height: 0)
            }
            .frame(width: 0, height: 0)
        }
        // Fill the detail column so the flexible PreviewPane can expand and the
        // transport bar sits at the bottom (Figma 318:1252), instead of the
        // content sizing to ~480pt and floating in a taller column.
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        // No outer padding: Figma 318:1228's Body is edge-to-edge, so the
        // transport and LTC strip are full-bleed (flush to the column's left /
        // right and the window bottom). Content insets live inside each section
        // (switcher 16 leading, waveform well 16 horizontal).
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: MediaImporter.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handlePickerResult
        )
        // Relink uses an AppKit NSOpenPanel (not a second .fileImporter): two
        // SwiftUI importers on one view are unreliable, and the dismissal
        // binding raced the completion handler so relink silently no-op'd
        // (#583). The panel is driven off `relinkTarget`.
        .onChange(of: relinkTarget) { _, newValue in
            guard let itemID = newValue else { return }
            // Defer so the "Missing media" alert finishes dismissing before the
            // open panel runs — a nested modal started inside the alert-dismiss
            // transaction never becomes key and the panel never appears (#587).
            DispatchQueue.main.async { presentRelinkPanel(itemID: itemID) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            importURLs(urls)
            return true
        }
        .alert(item: $pendingAlert, content: alertContent)
        .onReceive(NotificationCenter.default.publisher(for: .importMediaRequested)) { _ in
            showImporter = true
        }
        .playbackRateBindings(engine: engine, ltcEnabled: ltcRoutingStore.settings.isEnabled)
        .templateMenuReceiver(
            document: document,
            pendingErrorMessage: pendingAlertMessageBinding,
            undoManager: undoManager
        )
        .cueTransferMenuReceiver(document: document, undoManager: undoManager)
        .bundleExportMenuReceiver(document: document)
        .potPlayerExportMenuReceiver(document: document)
    }

    private func alertContent(_ alert: DocumentAlert) -> Alert {
        switch alert {
        case .unsupported(let message):
            return Alert(
                title: Text("Unsupported file"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        case let .relink(itemID, displayName):
            return Alert(
                title: Text("Missing media"),
                message: Text("\(displayName) couldn't be opened from its saved location."),
                primaryButton: .default(Text("Relink media…")) { relinkTarget = itemID },
                secondaryButton: .cancel(Text("Continue without media"))
            )
        }
    }

    private func reloadActive() async {
        guard document.model.activeItemID != nil else {
            await engine.unload()
            return
        }
        do {
            try await MediaImporter.loadActive(into: document, engine: engine, documentDirectory: documentDirectory)
        } catch {
            guard let item = document.model.activeItem else { return }
            pendingAlert = .relink(itemID: item.id, displayName: item.media.displayName)
        }
    }

}

/// Playhead / cue-creation actions. Split into an extension so the main
/// `DocumentView` body stays under the SwiftLint `type_body_length` cap.
extension DocumentView {

    /// Hidden `T`-key shortcut that stamps the next queued lyric line at the
    /// playhead — tap-along placement. Enabled only in Lyric mode.
    fileprivate var lyricTapAlongShortcut: some View {
        Button("Stamp Lyric Line") { stampLyricAtPlayhead() }
            .keyboardShortcut("t", modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .disabled(editorMode != .lyric || document.model.activeItem == nil)
    }

    /// Places the resolved cursor line at the current playhead and advances the
    /// cursor to the next unplaced line.
    fileprivate func stampLyricAtPlayhead() {
        guard let item = document.model.activeItem,
              let targetID = lyricsCursor.resolvedCursorID(unplaced: item.lyrics.unplacedLines)
        else { return }
        CueCommands.placeLyricLine(
            id: targetID,
            atMediaTime: engine.currentTime,
            itemID: item.id,
            document: document,
            undoManager: undoManager
        )
        lyricsCursor.advance(
            afterPlacing: targetID,
            remainingUnplaced: document.model.activeItem?.lyrics.unplacedLines ?? []
        )
    }

    func triggerHotkey(_ digit: Int) {
        guard canCreateCue else { return } // no cue creation in Show mode (#592)
        guard let type = document.model.cuePointType(forHotkey: digit) else { return }
        CueCommands.addCueAtPlayhead(
            time: engine.currentTime,
            typeID: type.id,
            document: document,
            undoManager: undoManager
        )
    }

}

enum DocumentAlert: Identifiable {
    case unsupported(String)
    case relink(itemID: MediaItem.ID, displayName: String)

    var id: String {
        switch self {
        case .unsupported(let message): "unsupported:\(message)"
        case let .relink(itemID, _): "relink:\(itemID.uuidString)"
        }
    }
}
