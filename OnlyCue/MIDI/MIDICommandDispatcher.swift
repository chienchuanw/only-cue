import Foundation

/// A snapshot of the engine state the pure resolver needs — passed in so the
/// resolver stays free of `@MainActor` / live objects and is unit-testable.
struct MIDIEngineSnapshot: Equatable {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let rateRange: ClosedRange<Float>
}

/// The concrete effect a matched MIDI action produces. The host executes it
/// against the live engine / stores / `CueCommands`.
enum MIDIEffect: Equatable {
    case seek(TimeInterval)
    case setRate(Float)
    case setLTCLevel(Float)
    case keymap(KeymapAction)
}

/// Pure resolver: `(action, value, engine snapshot) → effect`. Continuous
/// targets scale via `MIDISignal` (absolute snap, spec decision); discrete
/// actions pass through as `.keymap` for the host to route to the same
/// primitives OSC uses. Pinned by `MIDICommandDispatcherTests`.
enum MIDICommandDispatcher {
    static func effect(for action: MIDIAction, value: UInt8, engine: MIDIEngineSnapshot) -> MIDIEffect? {
        switch action {
        case .continuous(.scrub):
            return .seek(MIDISignal.scrubTime(value: value, duration: engine.duration))
        case .continuous(.playbackRate):
            return .setRate(MIDISignal.playbackRate(value: value, range: engine.rateRange))
        case .continuous(.ltcLevel):
            return .setLTCLevel(MIDISignal.ltcLevel(value: value))
        case .discrete(let keymapAction):
            return .keymap(keymapAction)
        }
    }
}
