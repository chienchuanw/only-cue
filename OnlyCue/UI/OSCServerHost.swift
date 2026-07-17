import SwiftUI

/// View modifier that owns the per-document `OSCServer`, starts/stops it based
/// on the global `@AppStorage` settings, and dispatches incoming `OSCCommand`s
/// to the document's `PlayerEngine` / `CueCommands`. Extracted from
/// `DocumentView` so the server's `@State` (and the seek-task cancellation
/// state) lives next to its dispatch logic and `DocumentView` stays under
/// SwiftLint's `type_body_length` cap — same pattern as `ExportSheetPresenter`
/// and `TemplateMenuReceiver`.
///
/// Multiple open documents: each gets its own `OSCServer`, all binding the
/// same UDP port with `allowLocalEndpointReuse`. On Darwin, an incoming
/// unicast datagram (what Companion / StreamDeck / grandMA3 send) is delivered
/// to exactly one of the bound sockets, chosen by the kernel — so with two
/// document windows open, one unpredictable document responds. OSC control
/// implies a single-document show-calling workflow; see ADR-016.
struct OSCServerHost: ViewModifier {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    var undoManager: UndoManager?
    /// Current editor mode, so `/cue/add` can be ignored in read-only Show mode
    /// while transport + cue navigation stay live (#592).
    var editorMode: EditorMode
    /// The resolved Show-mode GO/step cue-type filter (#657): nil = All cues.
    /// Non-nil only in Show mode with a live type selected, so `/cue/next`,
    /// `/cue/prev`, and `/cue/go` walk that type only — matching the in-app UI.
    var showGoTypeID: CuePointType.ID?

    @AppStorage(OSCServerSettings.enabledKey) private var enabled = false
    @AppStorage(OSCServerSettings.portKey) private var port = OSCServerSettings.defaultPort
    @State private var server = OSCServer()
    @State private var seekTask: Task<Void, Never>?
    @State private var showMonitor = false

    func body(content: Content) -> some View {
        content
            .onAppear { syncServer() }
            .onChange(of: enabled) { _, _ in syncServer() }
            .onChange(of: port) { _, _ in syncServer() }
            // Rebind the command handler so it captures the current editor mode
            // (the closure snapshots `self`); otherwise the Show-mode guard
            // would use the mode at server-start time (#592). The same closure
            // snapshots `showGoTypeID`, so rebind when the filter changes too so
            // OSC cue navigation follows the selected type (#657).
            .onChange(of: editorMode) { _, _ in syncServer() }
            .onChange(of: showGoTypeID) { _, _ in syncServer() }
            .onDisappear { server.stop() }
            .onReceive(NotificationCenter.default.publisher(for: .oscMonitorRequested)) { _ in
                showMonitor = true
            }
            .sheet(isPresented: $showMonitor) {
                OSCMonitorView(server: server)
            }
    }

    private func syncServer() {
        server.onCommand = { dispatch($0) }
        if enabled {
            server.start(port: UInt16(clamping: port))
        } else {
            server.stop()
        }
    }

    private func dispatch(_ command: OSCCommand) {
        if let target = Self.resolvedSeekTime(for: command, currentTime: engine.currentTime) {
            if case .stop = command { engine.pause() }
            seek(to: target)
            return
        }
        switch command {
        case .play: engine.play()
        case .pause: engine.pause()
        case .cueAdd:
            // Read-only Show mode forbids cue creation by any means (#592).
            guard CueCreationGate.allows(editorMode: editorMode, hasActiveItem: document.model.activeItem != nil) else { break }
            CueCommands.addCueAtPlayhead(time: engine.currentTime, document: document, undoManager: undoManager)
        case .cueNext: step(.next)
        case .cuePrev: step(.previous)
        case .cueGo: goNextCueAndPlay()
        case .stop, .skip, .locate: break // handled above
        }
    }

    /// Show-mode GO (#645): seek to the next cue after the playhead and play.
    /// No-op when there is no next cue. Not mode-gated — an external sender
    /// fires it deliberately.
    private func goNextCueAndPlay() {
        guard let item = document.model.activeItem,
              case .seekAndPlay(let time) = item.showGoDecision(from: engine.currentTime, typeID: showGoTypeID)
        else { return }
        // Seek *then* play in the same task (matching `DocumentView.performGo`),
        // so playback doesn't briefly start at the old playhead before the async
        // seek lands.
        seekTask?.cancel()
        seekTask = Task {
            await engine.seek(to: time)
            engine.play()
        }
    }

    /// The resolved absolute seek destination for a seek-y command, clamped to
    /// >= 0. nil for commands that aren't seeks. Pure — pinned by
    /// `OSCServerHostTests`. (`stop` rewinds to 0; `skip` is relative; `locate`
    /// is absolute.)
    static func resolvedSeekTime(for command: OSCCommand, currentTime: TimeInterval) -> TimeInterval? {
        switch command {
        case .stop: 0
        case .skip(let seconds): max(0, currentTime + seconds)
        case .locate(let seconds): max(0, seconds)
        default: nil
        }
    }

    private func seek(to time: TimeInterval) {
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: time) }
    }

    private func step(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction, typeID: showGoTypeID)
        else { return }
        seek(to: target.time)
    }
}

extension View {
    func oscServerHost(
        engine: PlayerEngine,
        document: CueListDocument,
        undoManager: UndoManager?,
        editorMode: EditorMode,
        showGoTypeID: CuePointType.ID?
    ) -> some View {
        modifier(OSCServerHost(
            engine: engine,
            document: document,
            undoManager: undoManager,
            editorMode: editorMode,
            showGoTypeID: showGoTypeID
        ))
    }
}
