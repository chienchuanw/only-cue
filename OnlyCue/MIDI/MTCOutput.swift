import CoreMIDI
import Foundation

/// Streams MIDI Timecode to the destination the user picked (epic #794) — the
/// transport half of the MTC generator.
///
/// Pushes two message shapes through `MTCPortSender`:
///
/// - **Quarter-frames** while the transport runs. A refill timer asks
///   `MTCSchedule` for the next window and hands the whole batch over with
///   **future** timestamps, so CoreMIDI's own scheduler delivers each message on
///   time. A main-actor stall therefore cannot jitter the stream — it can only
///   delay the *next* refill, which the look-ahead absorbs. The same reasoning
///   as `LTCAudioOutput.primeCount`.
/// - **Full Frame** on every locate (play-start, seek, scrubbing while paused,
///   and the Settings test button), so a receiver jumps immediately instead of
///   waiting two frames for eight quarter-frames to assemble.
///
/// It free-runs from an anchor rather than chasing the player's clock, for the
/// same reason the LTC engine does — and, because both consume the identical
/// `Timecode` from `ProjectTimecodeSettings`, the two outputs cannot disagree.
///
/// Caller responsibilities (see `MTCOutputHost`): call `start`/`stop` alongside
/// transport play/pause, `update(at:)` on a seek while playing, and
/// `locateWhileStopped(at:destinationUID:)` on a scrub while paused.
///
/// **Not headless-testable** — the CoreMIDI wiring needs real hardware, exactly
/// as `LTCAudioOutput` and `MIDIInput` are. The pure parts (`MTCFrame`,
/// `MTCSchedule`, `MIDIUniversalPacket`) carry the test weight; this class is
/// verified by running the app against an interface (see the spec's checklist).
@MainActor
final class MTCOutput: ObservableObject {

    /// Whether quarter-frames are currently streaming.
    @Published private(set) var isRunning = false
    /// The timecode a receiver is assembling right now, for the status row and pill.
    @Published private(set) var currentTimecode: Timecode?
    /// Display name of the resolved destination, or `nil` when unresolved.
    @Published private(set) var connectedName: String?
    /// The most recent failure (e.g. the destination vanished), for UI to surface.
    @Published private(set) var lastError: String?

    /// How far ahead of the clock messages are scheduled. Comfortably longer
    /// than `refillInterval`, so one missed timer wake-up cannot gap the stream.
    private let lookAheadSeconds: Double = 0.2
    /// Refill cadence — several refills fit inside one look-ahead window.
    private let refillInterval: TimeInterval = 0.05
    /// Wall-clock length of the Settings test-timecode burst.
    private let testBurstSeconds: TimeInterval = 2.0

    private let ticksPerSecond = MTCSchedule.hostTicksPerSecond()
    private let sender = MTCPortSender()

    private var schedule: MTCSchedule?
    /// Host time up to which quarter-frames have already been handed to CoreMIDI.
    /// The next batch opens here, which is what makes the windows tile exactly.
    private var scheduledUpTo: UInt64 = 0
    private var refillTimer: DispatchSourceTimer?
    private var testStopWorkItem: DispatchWorkItem?

    init() {
        sender.onEndpointsChanged = { [weak self] in self?.republishSenderState() }
    }

    /// Every connected MIDI destination, as `(uid, name)` for the Settings picker.
    nonisolated static func availableDestinations() -> [(uid: String, name: String)] {
        MTCPortSender.availableDestinations()
    }

    // MARK: - Transport hooks

    /// Begin (or restart) MTC output at `timecode`, sending to `destinationUID`.
    /// A no-op with a recorded error if the destination cannot be resolved.
    func start(at timecode: Timecode, destinationUID: String?) {
        cancelTestBurst()
        guard resolve(destinationUID) else {
            stopStream()
            return
        }
        anchor(at: timecode)
        startRefillTimer()
        isRunning = true
    }

    /// Stop the quarter-frame stream and release the schedule. Leaves the client
    /// and port open so a later `start` re-arms without recreating anything.
    func stop() {
        cancelTestBurst()
        stopStream()
    }

    /// Move the stream to `timecode` after a seek: re-anchor and re-cue with a
    /// Full Frame, so a receiver jumps rather than sliding into the new position.
    /// No-op if not running.
    func update(at timecode: Timecode) {
        guard isRunning else { return }
        anchor(at: timecode)
    }

    /// Send a single Full Frame without starting the stream — the paused-scrub
    /// path. Resolves the destination on demand, so it works with the transport
    /// stopped. Ignored while running, where `update(at:)` owns re-cueing.
    func locateWhileStopped(at timecode: Timecode, destinationUID: String?) {
        guard !isRunning, resolve(destinationUID) else { return }
        sendFullFrame(timecode)
        currentTimecode = timecode
    }

    /// Send a Full Frame plus a short quarter-frame burst at `timecode`, so the
    /// rig can be proven at setup rather than at showtime. Refused while the
    /// transport is driving output, where it would fight the real stream.
    func sendTestTimecode(at timecode: Timecode, destinationUID: String?) {
        guard !isRunning else {
            lastError = "Stop playback before sending test timecode."
            return
        }
        guard resolve(destinationUID) else { return }
        anchor(at: timecode)
        startRefillTimer()
        isRunning = true

        let stop = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.stopStream() }
        }
        testStopWorkItem = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + testBurstSeconds, execute: stop)
    }

    // MARK: - Anchoring

    /// Point a fresh `MTCSchedule` at `timecode` starting now, and locate the
    /// receiver there. Every entry into a new position goes through here, so the
    /// piece sequence always restarts at 0 on a clean group boundary.
    private func anchor(at timecode: Timecode) {
        let now = mach_absolute_time()
        schedule = MTCSchedule(startTimecode: timecode, anchorHostTime: now, ticksPerSecond: ticksPerSecond)
        scheduledUpTo = now
        currentTimecode = timecode
        sendFullFrame(timecode)
        topUpQuarterFrames()
    }

    private func stopStream() {
        stopRefillTimer()
        schedule = nil
        scheduledUpTo = 0
        isRunning = false
    }

    private func cancelTestBurst() {
        testStopWorkItem?.cancel()
        testStopWorkItem = nil
    }

    // MARK: - Sending

    /// Hand the sender every quarter-frame due between what has already been
    /// scheduled and the look-ahead horizon.
    ///
    /// The window is half-open and opens exactly where the last one closed, so
    /// each message is sent once — no duplicate at the seam, no gap across it.
    /// Because the timestamps are in the future, a late timer tick delays only
    /// the next refill, never delivery of what is already queued.
    private func topUpQuarterFrames() {
        guard let plan = schedule else { return }
        let horizon = mach_absolute_time() &+ UInt64(lookAheadSeconds * ticksPerSecond)
        guard horizon > scheduledUpTo else { return }

        let messages = plan.batch(from: scheduledUpTo, until: horizon)
        scheduledUpTo = horizon
        guard !messages.isEmpty else { return }

        sender.send(messages.map { message in
            MTCPortSender.Event(
                timestamp: message.timestamp,
                words: [MIDIUniversalPacket.systemCommonWord(
                    status: MTCFrame.quarterFrameStatus, data1: message.byte, data2: 0
                )]
            )
        })
        refreshCurrentTimecode(plan: plan)
        republishSenderState()
    }

    /// Send the Full Frame SysEx that locates a receiver to `timecode`. Timed
    /// "now" — a timestamp of 0 tells CoreMIDI to deliver immediately.
    private func sendFullFrame(_ timecode: Timecode) {
        let words = MIDIUniversalPacket.sysEx7Words(payload: MTCFrame.fullFrameBytes(timecode))
        guard !words.isEmpty else { return }
        sender.send([MTCPortSender.Event(timestamp: 0, words: words)])
        republishSenderState()
    }

    /// Update the published readout from how far the anchor has advanced — the
    /// value a receiver is assembling now, not the one furthest scheduled ahead.
    private func refreshCurrentTimecode(plan: MTCSchedule) {
        let elapsed = Double(mach_absolute_time() &- plan.anchorHostTime)
        let ticksPerSequence = plan.ticksPerQuarterFrame * Double(MTCFrame.piecesPerTimecode)
        guard ticksPerSequence > 0 else { return }
        currentTimecode = plan.timecode(forSequence: Int(elapsed / ticksPerSequence))
    }

    @discardableResult
    private func resolve(_ destinationUID: String?) -> Bool {
        let resolved = sender.resolve(uid: destinationUID)
        republishSenderState()
        return resolved
    }

    private func republishSenderState() {
        if connectedName != sender.connectedName { connectedName = sender.connectedName }
        if lastError != sender.lastError { lastError = sender.lastError }
    }

    // MARK: - Refill timer

    private func startRefillTimer() {
        stopRefillTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + refillInterval, repeating: refillInterval)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.topUpQuarterFrames() }
        }
        refillTimer = timer
        timer.resume()
    }

    private func stopRefillTimer() {
        refillTimer?.cancel()
        refillTimer = nil
    }
}
