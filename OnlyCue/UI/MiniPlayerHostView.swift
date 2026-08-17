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
    /// Shared seek-task box — owned by `DocumentView` so the key monitor and
    /// the host buttons use one `SeekTaskBox`, preventing overlapping seeks (#743).
    let seekBox: SeekTaskBox

    var body: some View {
        let actions = MiniPlaybackActions(
            engine: engine,
            document: document,
            context: context,
            ltcEnabled: LTCRoutingStore.shared.settings.isEnabled,
            seekTaskBox: seekBox
        )
        let model = MiniPlayerModel.make(
            currentTime: engine.currentTime,
            duration: engine.duration,
            item: document.model.activeItem,
            timecodeSettings: document.model.timecodeSettings,
            cuePointTypes: document.model.cuePointTypes,
            editorMode: context.editorMode,
            showGoTypeID: context.showGoTypeID
        )
        MiniPlayerView(
            model: model,
            isPlaying: engine.isPlaying,
            onPlayPause: { actions.playPause() },
            onPrevCue: { actions.stepCue(.previous) },
            onNextCue: { actions.stepCue(.next) },
            onPrevSong: { stepSong(.previous) },
            onNextSong: { stepSong(.next) },
            onGo: { actions.go() },
            onSeek: { actions.seek(toFraction: $0) },
            canPrevSong: CueCommands.canStepSong(.previous, activeID: document.model.activeItemID, in: document.model.items),
            canNextSong: CueCommands.canStepSong(.next, activeID: document.model.activeItemID, in: document.model.items),
            canPrevCue: hasCue(.previous),
            canNextCue: hasCue(.next)
        )
    }

    /// Whether a prev / next cue exists relative to the playhead (#753) — mirrors
    /// `MiniPlaybackActions.stepCue`'s walk so the button disables exactly when the seek would no-op.
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

}
