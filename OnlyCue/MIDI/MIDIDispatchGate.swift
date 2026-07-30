import Foundation

/// Whether an incoming message should actually fire its bound action, and what
/// value it carries. Pure, so the host's CoreMIDI callback stays a thin shell —
/// pinned by `MIDIInputHostTests`.
enum MIDIDispatchGate {
    /// Discrete actions fire on the press edge only, so a button's release
    /// (Note-off, or a CC falling back below 64) never double-fires.
    static func shouldFireDiscrete(_ message: MIDIMessage, previousCCValue: UInt8?) -> Bool {
        MIDISignal.isPressEdge(message, previousCCValue: previousCCValue)
    }

    /// Minimum spacing between continuous applications: ~one display frame.
    /// A motorised fader or a fast hand emits CC far quicker than the seek path
    /// (or a `UserDefaults` write) can absorb, so a sweep is coalesced to frame
    /// cadence. The caller is responsible for re-firing the last coalesced value
    /// once the window closes, so the fader's resting position always lands.
    static let continuousInterval: TimeInterval = 1.0 / 60.0

    /// Continuous targets track the sweep rather than an edge, so the only
    /// question is whether enough time has passed since the last application.
    /// `now` and `lastFiredAt` come from a monotonic clock in the caller — this
    /// stays pure so the cadence is unit-testable.
    static func shouldFireContinuous(now: TimeInterval, lastFiredAt: TimeInterval?) -> Bool {
        guard let lastFiredAt else { return true }
        return now - lastFiredAt >= continuousInterval
    }

    /// How long until the coalescing window closes, for scheduling the trailing
    /// re-fire. Zero when it is already open.
    static func continuousDelay(now: TimeInterval, lastFiredAt: TimeInterval?) -> TimeInterval {
        guard let lastFiredAt else { return 0 }
        return max(0, continuousInterval - (now - lastFiredAt))
    }

    /// The 0…127 payload: Note velocity or CC value.
    static func value(of message: MIDIMessage) -> UInt8 {
        switch message {
        case .note(_, _, let velocity): velocity
        case .controlChange(_, _, let value): value
        }
    }
}
