import Foundation

/// Pure helpers turning a `MIDIMessage` into either a discrete "press" decision
/// or a scaled continuous value. Hardware-free; pinned by `MIDISignalTests`.
///
/// Discrete press semantics (spec default #2): a Note fires when velocity > 0; a
/// CC fires only on the rising edge that crosses the 64 midpoint (`<64 → ≥64`),
/// so a button's release (value 0) never double-fires.
enum MIDISignal {
    static func isPressEdge(_ message: MIDIMessage, previousCCValue: UInt8?) -> Bool {
        switch message {
        case .note(_, _, let velocity):
            return velocity > 0
        case .controlChange(_, _, let value):
            let wasBelow = (previousCCValue ?? 0) < 64
            return wasBelow && value >= 64
        }
    }

    static func normalized(_ value: UInt8) -> Double { Double(value) / 127.0 }

    static func scrubTime(value: UInt8, duration: TimeInterval) -> TimeInterval {
        normalized(value) * duration
    }

    static func playbackRate(value: UInt8, range: ClosedRange<Float>) -> Float {
        range.lowerBound + Float(normalized(value)) * (range.upperBound - range.lowerBound)
    }

    static func ltcLevel(value: UInt8) -> Float { Float(normalized(value)) }
}
