import Foundation

/// Pure copy + state machine for the two MTC status surfaces (epic #794): the
/// row in Settings ▸ MIDI and the pill beside the playhead clock.
///
/// Both read the same `MTCOutput` state, so the mapping from that state to words
/// and to a visual treatment lives here once rather than being reimplemented on
/// each surface. Follows `LTCBadgeLabel`, which pins its formatting the same way.
enum MTCStatusLabel {

    /// What the surfaces render. `failed` outranks `sending`: a destination that
    /// vanished mid-show must read as broken even while the generator still
    /// believes it is running.
    enum State: Equatable {
        case off
        case ready
        case sending
        case failed
    }

    /// The pill's caption — a fixed token, so the transport bar's layout cannot
    /// shift as the timecode advances.
    static let pillText = "MTC"

    /// Whether the transport pill should appear at all. Tied to the user's
    /// enable switch rather than to whether output is running, so an armed-but-idle
    /// setup is still visible — and an unconfigured install carries no dead chrome.
    static func isPillVisible(isEnabled: Bool) -> Bool { isEnabled }

    static func state(isComplete: Bool, isRunning: Bool, lastError: String?) -> State {
        if lastError != nil { return .failed }
        guard isComplete else { return .off }
        return isRunning ? .sending : .ready
    }

    static func statusText(state: State, timecode: String?, lastError: String?) -> String {
        switch state {
        case .failed:
            return lastError ?? "MTC output failed."
        case .off:
            return "Not sending — enable MTC and choose a destination."
        case .ready:
            return "Ready — sends on play."
        case .sending:
            guard let timecode else { return "Sending" }
            return "Sending — \(timecode)"
        }
    }
}
