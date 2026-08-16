import SwiftUI

extension DocumentView {

    /// Seeks the playhead by `seconds` relative to the current position,
    /// clamping at zero. Cancels any in-flight seek before starting a new one.
    func jump(by seconds: TimeInterval) {
        let target = max(0, engine.currentTime + seconds)
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target) }
    }

    /// Stamps a new cue at the current playhead position using the document's
    /// default cue type. No-ops in Show mode (#592).
    func addCueAtPlayhead() {
        guard canCreateCue else { return } // no cue creation in Show mode (#592)
        CueCommands.addCueAtPlayhead(
            time: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }
}
