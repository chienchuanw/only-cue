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
            onPrevSong: { stepSong(.previous) },
            onNextSong: { stepSong(.next) },
            onGo: { performGo() },
            canPrevSong: canStepSong(.previous),
            canNextSong: canStepSong(.next),
            canPrevCue: hasCue(.previous),
            canNextCue: hasCue(.next)
        )
    }

    /// Whether a prev / next song exists to step to — list position only (#753).
    private func canStepSong(_ direction: MediaItem.PlayheadStep) -> Bool {
        guard let id = document.model.activeItemID else { return false }
        switch direction {
        case .previous: return CueCommands.previousMediaItemID(before: id, in: document.model.items) != nil
        case .next: return CueCommands.nextMediaItemID(after: id, in: document.model.items) != nil
        }
    }

    /// Whether a prev / next cue exists relative to the playhead (#753) — mirrors
    /// `step`'s walk so the button disables exactly when the seek would no-op.
    private func hasCue(_ direction: MediaItem.PlayheadStep) -> Bool {
        document.model.activeItem?.cue(
            steppingFrom: engine.currentTime,
            direction: direction,
            typeID: context.showGoTypeID
        ) != nil
    }

    /// Prev/next-song: switch media item and play immediately (#753) — routes
    /// through `CueCommands`, mirroring `DocumentView.stepSong`. Relink failures
    /// surface in the main window; the mini player just stays put.
    private func stepSong(_ direction: MediaItem.PlayheadStep) {
        Task {
            await CueCommands.stepMediaAndPlay(
                direction,
                document: document,
                reloadAndPlay: { _ in
                    do {
                        try await MediaImporter.loadActive(into: document, engine: engine)
                        engine.play()
                    } catch {
                        // No relink UI in the mini panel — leave state unchanged.
                    }
                }
            )
        }
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
