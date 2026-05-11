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
            CueCommands.addCueAtPlayhead(time: engine.currentTime, document: document, undoManager: undoManager)
        case .cueNext: step(.next)
        case .cuePrev: step(.previous)
        case .stop, .skip, .locate: break // handled above
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
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction)
        else { return }
        seek(to: target.time)
    }
}

extension View {
    func oscServerHost(
        engine: PlayerEngine,
        document: CueListDocument,
        undoManager: UndoManager?
    ) -> some View {
        modifier(OSCServerHost(engine: engine, document: document, undoManager: undoManager))
    }
}
