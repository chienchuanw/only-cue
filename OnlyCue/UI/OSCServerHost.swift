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
/// same UDP port with `allowLocalEndpointReuse`. A `/onlycue/play` then plays
/// every open document. Acceptable for v1 (most users have one document); see
/// ADR-016.
struct OSCServerHost: ViewModifier {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    var undoManager: UndoManager?

    @AppStorage("oscServerEnabled") private var enabled = false
    @AppStorage("oscServerPort") private var port = Int(OSCServer.defaultPort)
    @State private var server = OSCServer()
    @State private var seekTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { syncServer() }
            .onChange(of: enabled) { _, _ in syncServer() }
            .onChange(of: port) { _, _ in syncServer() }
            .onDisappear { server.stop() }
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
        switch command {
        case .play:
            engine.play()
        case .pause:
            engine.pause()
        case .stop:
            engine.pause()
            seek(to: 0)
        case .skip(let seconds):
            seek(to: max(0, engine.currentTime + seconds))
        case .locate(let seconds):
            seek(to: max(0, seconds))
        case .cueAdd:
            CueCommands.addCueAtPlayhead(time: engine.currentTime, document: document, undoManager: undoManager)
        case .cueNext:
            step(.next)
        case .cuePrev:
            step(.previous)
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
