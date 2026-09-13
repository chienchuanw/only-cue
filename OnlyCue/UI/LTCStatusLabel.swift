import Foundation

/// Pure copy + state machine for the LTC status pill beside the playhead clock
/// (#796). Closes the same showtime-invisibility gap `MTCStatusLabel` closed for
/// MIDI Timecode (#794): `LTCAudioOutput.lastError` is published but was unread,
/// so a routed interface that vanished stopped timecode with no operator signal.
///
/// The mapping from `LTCAudioOutput` / `LTCRoutingSettings` state to words and a
/// visual treatment lives here once so the pill carries no logic of its own —
/// the same shape as `MTCStatusLabel` and `LTCBadgeLabel`.
enum LTCStatusLabel {

    /// What the pill renders. `failed` outranks `sending`: an interface that
    /// vanished mid-show must read as broken even while the engine still believes
    /// it is running.
    enum State: Equatable {
        case off
        case ready
        case sending
        case failed
    }

    /// The pill's caption — a fixed token, so the transport bar's layout cannot
    /// shift as the timecode advances.
    static let pillText = "LTC"

    /// Whether the pill should appear at all. Tied to the user's master enable
    /// switch (`LTCRoutingSettings.isEnabled`) rather than to whether output is
    /// running, so an armed-but-idle rig is still visible — and an unconfigured
    /// install carries no dead chrome.
    static func isPillVisible(isEnabled: Bool) -> Bool { isEnabled }

    static func state(isComplete: Bool, isRunning: Bool, lastError: String?) -> State {
        if lastError != nil { return .failed }
        guard isComplete else { return .off }
        return isRunning ? .sending : .ready
    }

    static func statusText(state: State, timecode: String?, lastError: String?) -> String {
        switch state {
        case .failed:
            return lastError ?? "LTC output failed."
        case .off:
            return "Not sending — enable LTC and assign an output channel."
        case .ready:
            return "Ready — sends on play."
        case .sending:
            // LTC publishes no live timecode; the label keeps `MTCStatusLabel`'s
            // signature so the two surfaces stay interchangeable, and the giant
            // playhead clock sits adjacent when no timecode is supplied.
            guard let timecode else { return "Sending" }
            return "Sending — \(timecode)"
        }
    }
}
