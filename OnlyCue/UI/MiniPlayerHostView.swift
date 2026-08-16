import SwiftUI

/// The reactive content hosted inside the Mini Player panel. Derives a fresh
/// `MiniPlayerModel` from the shared engine + document + context on every change
/// and wires the transport buttons to the same seek/play seams the main window
/// uses (`MediaItem.cue(steppingFrom:)`, `showGoDecision`). Reads only reference
/// / observable state so it stays live for the panel's whole lifetime.
struct MiniPlayerHostView: View {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    let context: MiniPlayerContext

    @State private var seekTask: Task<Void, Never>?

    var body: some View {
        let model = MiniPlayerModel.make(
            currentTime: engine.currentTime,
            item: document.model.activeItem,
            timecodeSettings: document.model.timecodeSettings,
            cuePointTypes: document.model.cuePointTypes,
            editorMode: context.editorMode,
            showGoTypeID: context.showGoTypeID
        )
        MiniPlayerView(
            model: model,
            isPlaying: engine.isPlaying,
            onPlayPause: { engine.toggle() },
            onPrevCue: { step(.previous) },
            onNextCue: { step(.next) },
            onGo: { performGo() }
        )
    }

    /// Prev/next-cue: seek only, honouring the Show-mode type filter — mirrors
    /// `DocumentView.stepPlayhead`.
    private func step(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(
                  steppingFrom: engine.currentTime,
                  direction: direction,
                  typeID: context.showGoTypeID
              )
        else { return }
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target.time) }
    }

    /// Show-mode GO: seek to the next cue and play — mirrors `DocumentView.performGo`.
    private func performGo() {
        guard let item = document.model.activeItem,
              case .seekAndPlay(let time) = item.showGoDecision(
                  from: engine.currentTime,
                  typeID: context.showGoTypeID
              )
        else { return }
        seekTask?.cancel()
        seekTask = Task {
            await engine.seek(to: time)
            engine.play()
        }
    }
}
