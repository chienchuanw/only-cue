import SwiftUI

extension DocumentView {

    /// Pause-at-each-cue: auto-pause + select-the-crossed-cue when playback
    /// crosses a cue. `engine.rate > 0` guard skips scrubs during pause; the
    /// helper's strict-`>` on previousTime avoids re-pausing on resume from a
    /// previously-paused-at cue. Selecting aligns inspector / cue-list /
    /// marker / auto-scroll.
    func handlePauseAtEachCue(from oldValue: TimeInterval, to newValue: TimeInterval) {
        guard pauseAtEachCue, engine.rate > 0 else { return }
        let cues = document.model.activeItem?.cues ?? []
        if let crossed = cues.cueCrossed(movingFrom: oldValue, to: newValue) {
            engine.pause()
            cueSelection = [crossed.id]
        }
    }
}
