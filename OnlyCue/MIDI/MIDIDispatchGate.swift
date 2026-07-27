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

    /// Continuous targets track every message — a fader mid-sweep must keep
    /// updating even though its value crosses no threshold.
    static func shouldFireContinuous(_ message: MIDIMessage) -> Bool { true }

    /// The 0…127 payload: Note velocity or CC value.
    static func value(of message: MIDIMessage) -> UInt8 {
        switch message {
        case .note(_, _, let velocity): velocity
        case .controlChange(_, _, let value): value
        }
    }
}
