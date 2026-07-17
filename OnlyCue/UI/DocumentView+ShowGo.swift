import SwiftUI

/// Cue-navigation actions extracted from `DocumentView` to keep its body under
/// the SwiftLint `file_length` cap: `stepPlayhead` (transport/OSC prev-next cue,
/// seek only) and `performGo` (Show-mode GO, seek + play).
extension DocumentView {

    /// Steps the playhead to the previous / next cue (transport prev/next-cue
    /// buttons, keyboard, OSC). Seeks without changing the play/pause state —
    /// unlike `performGo`, which also plays.
    func stepPlayhead(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction)
        else { return }
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target.time) }
    }

    /// Show-mode GO (#645): seek to the next cue after the playhead and play.
    /// No-op when there is no next cue. Not a `ProjectModel` mutation, so it
    /// drives the engine directly rather than going through `CueCommands`.
    /// Extracted from `DocumentView` to keep its body under the SwiftLint
    /// `file_length` cap.
    func performGo() {
        guard let item = document.model.activeItem,
              case .seekAndPlay(let time) = item.showGoDecision(from: engine.currentTime)
        else { return }
        seekTask?.cancel()
        seekTask = Task {
            await engine.seek(to: time)
            engine.play()
        }
    }
}
