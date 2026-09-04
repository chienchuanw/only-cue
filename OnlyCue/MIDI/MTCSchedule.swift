import Foundation

/// The timing plan for the MTC generator: a pure value type mapping host-clock
/// time to the quarter-frame bytes due at that time. `MTCOutput` owns one and
/// asks it for the next window; all the timecode/clock arithmetic lives here so
/// that side is just `MIDISendEventList` plumbing.
///
/// The MTC analogue of `LTCSchedule`, and free-running for the same reason:
/// timecode advances from an anchor at the nominal rate rather than chasing the
/// player's clock, so it cannot wobble — and so it cannot disagree with the LTC
/// engine, which free-runs from the identical `Timecode`. A seek builds a fresh
/// schedule rather than nudging this one.
///
/// **The two-frame convention.** Eight quarter-frames carry one complete value
/// and span two frames, so a receiver assembles a value two frames after the
/// sequence begins. v1 transmits the value **uncompensated** — the sequence
/// beginning at frame `N` carries `N`, and the receiver applies the offset — which
/// is the common reading of the spec. If hardware is found to read two frames
/// early, `timecode(forSequence:)` is the single place to compensate.
struct MTCSchedule: Equatable {

    /// One scheduled quarter-frame: the data byte and the host time it is due.
    struct Message: Equatable, Sendable {
        let byte: UInt8
        let timestamp: UInt64
    }

    /// Timecode carried by the first quarter-frame sequence.
    let startTimecode: Timecode
    /// Host-clock time (`mach_absolute_time` units) at which quarter-frame 0 is due.
    let anchorHostTime: UInt64
    /// Host-clock ticks per wall-clock second. Injected so tests are exact.
    let ticksPerSecond: Double

    init(startTimecode: Timecode, anchorHostTime: UInt64, ticksPerSecond: Double) {
        precondition(ticksPerSecond > 0, "host clock must advance")
        self.startTimecode = startTimecode
        self.anchorHostTime = anchorHostTime
        self.ticksPerSecond = ticksPerSecond
    }

    // MARK: - Cadence

    /// Host-clock ticks between consecutive quarter-frames — a quarter of a
    /// frame period, so 4 × the framerate messages per second.
    var ticksPerQuarterFrame: Double {
        ticksPerSecond / (Double(startTimecode.rate.framesPerSecond) * 4)
    }

    /// Timecode carried by quarter-frame sequence `index` (each sequence is
    /// eight messages and advances the value by two frames).
    func timecode(forSequence index: Int) -> Timecode {
        Timecode(
            frameCount: startTimecode.frameCount + max(0, index) * MTCFrame.framesPerSequence,
            rate: startTimecode.rate
        )
    }

    /// Host time at which quarter-frame `index` is due.
    func timestamp(forQuarterFrame index: Int) -> UInt64 {
        anchorHostTime &+ UInt64((Double(max(0, index)) * ticksPerQuarterFrame).rounded())
    }

    /// The data byte for quarter-frame `index`.
    func byte(forQuarterFrame index: Int) -> UInt8 {
        let position = max(0, index)
        return MTCFrame.quarterFrameByte(
            piece: position % MTCFrame.piecesPerTimecode,
            timecode: timecode(forSequence: position / MTCFrame.piecesPerTimecode)
        )
    }

    // MARK: - Windowing

    /// Every quarter-frame due in the **half-open** window `[from, until)`.
    ///
    /// Half-open is what lets the refill timer tile the timeline: passing the
    /// previous call's `until` as the next call's `from` yields each message
    /// exactly once, with no duplicate at the seam and no gap across it. A
    /// window opening before the anchor clamps to quarter-frame 0; an empty or
    /// inverted window yields nothing.
    func batch(from: UInt64, until: UInt64) -> [Message] {
        guard until > from else { return [] }
        let first = max(0, quarterFrameIndex(atOrAfter: from))
        let limit = max(0, quarterFrameIndex(atOrAfter: until))
        guard limit > first else { return [] }
        return (first..<limit).map { Message(byte: byte(forQuarterFrame: $0), timestamp: timestamp(forQuarterFrame: $0)) }
    }

    /// The lowest quarter-frame index whose timestamp is `>= time`.
    ///
    /// Rounded before the ceiling so a timestamp this type itself produced (which
    /// was rounded on the way out) maps back to its own index rather than to the
    /// next one — otherwise tiled windows would drop a message at every seam.
    private func quarterFrameIndex(atOrAfter time: UInt64) -> Int {
        let offset = Double(time) - Double(anchorHostTime)
        guard offset > 0 else { return 0 }
        let exact = offset / ticksPerQuarterFrame
        let rounded = (exact * 1_000_000).rounded() / 1_000_000
        return Int(rounded.rounded(.up))
    }
}

// MARK: - Host clock

extension MTCSchedule {

    /// Host-clock ticks per second for this machine, from `mach_timebase_info`.
    /// The one impure-ish call in the type, kept here so `MTCOutput` does not
    /// have to reach for Mach itself and tests can inject a value instead.
    static func hostTicksPerSecond() -> Double {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.numer > 0, timebase.denom > 0 else {
            return 1_000_000_000   // assume nanosecond ticks
        }
        return 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)
    }
}
