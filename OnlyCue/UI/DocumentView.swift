import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    @State var engine = PlayerEngine()
    @State private var showImporter = false
    @State var pendingAlert: DocumentAlert?
    @State private var seekTask: Task<Void, Never>?
    @State private var showOverlayAppearance = false
    @State var cueSelection: Set<Cue.ID> = []
    /// The unplaced-lyric-queue cursor — UI working state for placement.
    @State private var lyricsCursor = LyricsAuthoringCursor()
    @AppStorage(FirstLaunchFlag.key) var didShowFirstLaunch = false
    @AppStorage(NotesOverlayPreferences.storageKey) var overlayPrefsData = NotesOverlayPreferences.defaultEncoded
    @AppStorage("pauseAtEachCue") var pauseAtEachCue = false
    /// The editor mode — per-window working state, restored across relaunch.
    @SceneStorage("onlycue.editorMode") private var editorModeRaw = EditorMode.cue.rawValue
    @ObservedObject private var keymapStore = KeymapStore.shared
    /// Drives the main-view LTC strip's visibility — it appears whenever LTC
    /// routing is enabled. Observing the singleton here means flipping the
    /// switch in Preferences updates the strip in real time.
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared
    @Environment(\.undoManager) private var undoManager

    private func shortcut(_ action: KeymapAction) -> KeyboardShortcut {
        keymapStore.keymap.chord(for: action).keyboardShortcut
            ?? Keymap.default.chord(for: action).keyboardShortcut
            ?? KeyboardShortcut(KeyEquivalent("/"), modifiers: .command)
    }

    private var editorMode: EditorMode { EditorMode(rawValue: editorModeRaw) ?? .cue }

    var body: some View {
        NavigationSplitView {
            ItemListPane(document: document, onDropURLs: importURLs)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            mainPane
                .inspector(isPresented: .constant(true)) {
                    ModeAwareInspector(
                        document: document,
                        engine: engine,
                        editorMode: editorMode,
                        cueSelection: $cueSelection,
                        lyricsCursor: $lyricsCursor
                    )
                    .cueListInspectorColumnWidth()
                }
        }
        .navigationSubtitle(document.model.activeItem?.resolvedName ?? "")
        .sheet(isPresented: firstLaunchBinding) {
            FirstLaunchSheet { didShowFirstLaunch = true }
        }
        .task(id: document.model.activeItemID) { await reloadActive() }
        .stripedTimecodeReader(item: document.model.activeItem)
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
        .exportSheet(model: document.model, pendingErrorMessage: pendingAlertMessageBinding)
        .oscServerHost(engine: engine, document: document, undoManager: undoManager)
        .ltcOutput(engine: engine, document: document)
        .environment(\.projectFramerate, document.model.timecodeSettings.framerate)
    }

    private var mainPane: some View {
        let activeItem = document.model.activeItem
        return VStack(spacing: 12) {
            if activeItem == nil {
                DocumentEmptyState(onImport: { showImporter = true })
            } else {
                PreviewPane(
                    document: document,
                    engine: engine,
                    selectedCueIDs: cueSelection,
                    onSelectCue: { cueSelection = [$0] },
                    onToggleCue: { cueSelection.formSymmetricDifference([$0]) },
                    editorMode: editorMode,
                    setEditorMode: { editorModeRaw = $0.rawValue },
                    lyricsCursor: $lyricsCursor
                )
            }

            ltcStripIfEnabled(activeItem)

            TransportBar(
                engine: engine,
                cues: activeItem?.cues ?? [],
                mediaDuration: activeItem?.media.duration ?? 0,
                timecodeSettings: document.model.timecodeSettings,
                activeItem: activeItem
            )
                .padding(.top, 4)

            transportShortcuts
            digitShortcuts
            lyricTapAlongShortcut
            PlayheadStepShortcuts(
                onStepPrev: { stepPlayhead(.previous) },
                onStepNext: { stepPlayhead(.next) },
                isEnabled: document.model.activeItem != nil,
                shortcutFor: shortcut
            )
            PlaybackRateShortcuts(
                engine: engine,
                ltcEnabled: ltcRoutingStore.settings.isEnabled,
                shortcutFor: shortcut
            )
        }
        .frame(minWidth: 560, minHeight: 480)
        .padding()
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: MediaImporter.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handlePickerResult
        )
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
    }

    @ViewBuilder
    private func ltcStripIfEnabled(_ activeItem: MediaItem?) -> some View {
        if let activeItem, ltcRoutingStore.settings.isEnabled {
            LTCStrip(
                item: activeItem,
                framerate: document.model.timecodeSettings.framerate,
                duration: activeItem.media.duration,
                onToggleMute: {
                    CueCommands.setLTCMuted(
                        itemID: activeItem.id,
                        muted: !activeItem.ltcMuted,
                        document: document,
                        undoManager: undoManager
                    )
                }
            )
        }
    }

    private func alertContent(_ alert: DocumentAlert) -> Alert {
        switch alert {
        case .unsupported(let message):
            return Alert(
                title: Text("Unsupported file"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        case .relink(let displayName):
            return Alert(
                title: Text("Missing media"),
                message: Text("\(displayName) couldn't be opened from its saved location."),
                primaryButton: .default(Text("Relink media…")) { showImporter = true },
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
            try await MediaImporter.loadActive(into: document, engine: engine)
        } catch {
            pendingAlert = .relink(document.model.activeItem?.media.displayName ?? "The media file")
        }
    }

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importURLs(urls)
        case .failure(let error):
            pendingAlert = .unsupported(error.localizedDescription)
        }
    }

    private func importURLs(_ urls: [URL]) {
        Task { @MainActor in
            do {
                try await MediaImporter.importMedia(
                    from: urls,
                    into: document,
                    engine: engine,
                    undoManager: undoManager
                )
            } catch let MediaImportError.batch(unsupported) {
                pendingAlert = .unsupported(unsupportedMessage(unsupported))
            } catch {
                pendingAlert = .unsupported(error.localizedDescription)
            }
        }
    }

    private func unsupportedMessage(_ filenames: [String]) -> String {
        let list = filenames.joined(separator: ", ")
        return filenames.count == 1
            ? "\(list) isn't a supported audio or video file."
            : "These files weren't supported and were skipped: \(list)"
    }

    private var transportShortcuts: some View {
        ZStack {
            Button("Play/Pause") { engine.toggle() }
                .keyboardShortcut(shortcut(.playPause))
            Button("Back 1s") { jump(by: -1) }
                .keyboardShortcut(shortcut(.jumpBack))
            Button("Forward 1s") { jump(by: 1) }
                .keyboardShortcut(shortcut(.jumpForward))
            Button("Add Cue") { addCueAtPlayhead() }
                .keyboardShortcut(shortcut(.addCue))
                .disabled(document.model.activeItem == nil)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var digitShortcuts: some View {
        ZStack {
            ForEach(0...9, id: \.self) { digit in
                Button("Cue Type \(digit)") { triggerHotkey(digit) }
                    .keyboardShortcut(shortcut(KeymapAction.addCueOfType(digit) ?? .addCueOfType0))
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .disabled(document.model.activeItem == nil)
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

    fileprivate func triggerHotkey(_ digit: Int) {
        guard let type = document.model.cuePointType(forHotkey: digit) else { return }
        CueCommands.addCueAtPlayhead(
            time: engine.currentTime,
            typeID: type.id,
            document: document,
            undoManager: undoManager
        )
    }

    fileprivate func stepPlayhead(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction)
        else { return }
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target.time) }
    }

    fileprivate func jump(by seconds: TimeInterval) {
        let target = max(0, engine.currentTime + seconds)
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target) }
    }

    fileprivate func addCueAtPlayhead() {
        CueCommands.addCueAtPlayhead(
            time: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }
}

extension Notification.Name {
    static let importMediaRequested = Notification.Name("OnlyCue.importMediaRequested")
    static let exportCuesToCSVRequested = Notification.Name("OnlyCue.exportCuesToCSVRequested")
    static let saveTemplateRequested = Notification.Name("OnlyCue.saveTemplateRequested")
    static let loadTemplateRequested = Notification.Name("OnlyCue.loadTemplateRequested")
    static let oscMonitorRequested = Notification.Name("OnlyCue.oscMonitorRequested")
    static let timecodeSettingsRequested = Notification.Name("OnlyCue.timecodeSettingsRequested")
    static let snapSelectedCuesToBeat = Notification.Name("OnlyCue.snapSelectedCuesToBeat")
    static let snapSelectedCuesToBar = Notification.Name("OnlyCue.snapSelectedCuesToBar")
    static let manageTypesRequested = Notification.Name("OnlyCue.manageTypesRequested")
    static let editorModeChangeRequested = Notification.Name("OnlyCue.editorModeChangeRequested")
    static let playbackRateUp = Notification.Name("OnlyCue.playbackRateUp")
    static let playbackRateDown = Notification.Name("OnlyCue.playbackRateDown")
    static let playbackRateReset = Notification.Name("OnlyCue.playbackRateReset")
    static let playbackRateInterlockBlocked = Notification.Name("OnlyCue.playbackRateInterlockBlocked")
    static let playbackRateInterlockReset = Notification.Name("OnlyCue.playbackRateInterlockReset")
}

enum DocumentAlert: Identifiable {
    case unsupported(String)
    case relink(String)

    var id: String {
        switch self {
        case .unsupported(let message): "unsupported:\(message)"
        case .relink(let name): "relink:\(name)"
        }
    }
}
