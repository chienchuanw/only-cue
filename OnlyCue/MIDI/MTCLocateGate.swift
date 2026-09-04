import Foundation

/// The decisions `MTCOutputHost` makes on every playhead observation (epic
/// #794): whether a `currentTime` change is a seek, and whether a locate may go
/// out right now.
///
/// Pure and hardware-free, extracted for the same reason `MIDIDispatchGate` was
/// — the host is a SwiftUI modifier and awkward to exercise, while these rules
/// are exactly the part worth pinning.
enum MTCLocateGate {

    /// Playhead movement, in seconds, beyond which a change during playback is
    /// treated as a seek rather than ordinary progress.
    ///
    /// Normal playback advances roughly 0.1 s per observation, so this leaves
    /// headroom while still being far stricter than the LTC path's 1.0 s — MTC
    /// costs one message to re-cue, where LTC costs a buffer re-prime, so there
    /// is no reason to let a half-second jump slide.
    static let playingSeekEpsilon: TimeInterval = 0.25

    /// Movement below which a paused playhead is considered unchanged — floating
    /// point noise rather than a scrub.
    static let pausedEpsilon: TimeInterval = 1e-6

    /// Minimum spacing between locates, so dragging the waveform cannot flood
    /// the port with one Full Frame per pixel. ~10 per second.
    static let minimumLocateInterval: TimeInterval = 0.1

    /// Whether a `currentTime` change during playback is a seek.
    static func isSeekWhilePlaying(from oldValue: TimeInterval, to newValue: TimeInterval) -> Bool {
        abs(newValue - oldValue) > playingSeekEpsilon
    }

    /// Whether a `currentTime` change while paused should locate the receiver.
    /// Any real move counts — there is no stream to protect, and following a
    /// parked playhead is the point.
    static func isLocateWhilePaused(from oldValue: TimeInterval, to newValue: TimeInterval) -> Bool {
        abs(newValue - oldValue) > pausedEpsilon
    }

    /// Slack absorbing floating-point representation error in the comparison
    /// below: subtracting two timestamps one interval apart can land a hair
    /// under it (100.1 - 100.0 == 0.09999999999999432), which would otherwise
    /// refuse a caller that waited exactly long enough.
    private static let intervalTolerance: TimeInterval = 1e-9

    /// Whether enough time has passed since `lastSentAt` to send another locate.
    ///
    /// A `nil` timestamp (nothing sent yet) always passes. So does an apparently
    /// backwards clock, so a stale timestamp cannot latch the throttle closed.
    static func shouldSend(now: TimeInterval, lastSentAt: TimeInterval?) -> Bool {
        guard let lastSentAt else { return true }
        let elapsed = now - lastSentAt
        return elapsed < 0 || elapsed >= minimumLocateInterval - intervalTolerance
    }
}
