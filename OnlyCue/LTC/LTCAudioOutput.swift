import AVFoundation
import CoreAudio

/// Renders a continuous LTC signal onto a chosen Core Audio output device — the
/// `AVAudioEngine` half of epic #33's generator. Given the timecode at the
/// current playhead, the project framerate, and `LTCRoutingSettings`, it opens
/// an engine on the routed device and streams `LTCSchedule` buffers onto an
/// `AVAudioPlayerNode`, with the mono LTC placed on the channel the routing
/// assigned (`ChannelRole.ltc`) and silence on the others. When a
/// `ProgramAudioRingBuffer` is supplied to `start` (the media's program audio,
/// captured by `ProgramAudioTap`), a second `AVAudioPlayerNode` plays it onto
/// the routing's `trackLeft` / `trackRight` channels so the LTC channel never
/// sums with program audio. Rebuilds on `AVAudioEngineConfigurationChange`
/// (device disconnect / sample-rate change) from the timecode it was last told.
///
/// Caller responsibilities (see `LTCAudioOutput` consumers): call `start`/`stop`
/// alongside transport play/pause, and `update(timecode:)` on seek.
///
/// **Not headless-testable** — the engine + device wiring needs real Core Audio
/// hardware. The pure parts (`LTCSchedule`, `makeBuffer`) are unit-tested; this
/// class is verified by running the app against an interface.
@MainActor
final class LTCAudioOutput: ObservableObject {

    /// Whether the engine is currently producing LTC.
    @Published private(set) var isRunning = false
    /// The most recent failure (e.g. the routed device vanished), for UI to surface.
    @Published private(set) var lastError: String?

    /// Audio buffers kept scheduled ahead of the play head — enough that a brief
    /// main-actor stall (the buffer-refill hops through it) won't underrun.
    private let primeCount = 5
    /// Target wall-clock length of one scheduled buffer.
    private let bufferTargetSeconds: TimeInterval = 0.1

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// Sums the LTC node and the program node before the output node — the output
    /// node has a single input bus, so the two player nodes can't connect to it
    /// directly (the second `connect` would disconnect the first). The mixer's
    /// input and output formats are both `renderFormat` (same discrete channel
    /// layout), so it passes channels through 1:1 rather than downmixing.
    private let mixerNode = AVAudioMixerNode()
    private var schedule: LTCSchedule?
    /// Render format + LTC channel of the active engine connection — set by
    /// `restartEngine`, read by `scheduleOneBuffer` (so the off-thread completion
    /// handler hops back to `self` rather than capturing them across the actor).
    private var renderFormat: AVAudioFormat?
    private var ltcChannel = 0
    /// When true, the LTC channel emits silence on the next render block. The
    /// encoder keeps running so toggling is instant (no re-cue glitch). Toggled
    /// by `LTCOutputHost` from `MediaItem.ltcMuted` on the active item.
    private var isLTCMuted = false

    /// Second player node carrying the media's program audio onto the Track L / R
    /// channels while LTC runs (`LTCOutputHost` mutes `AVPlayer`'s own output and
    /// feeds this via a `ProgramAudioTap`). `nil` `programRing` ⇒ no program
    /// audio is scheduled, so those channels stay silent.
    private let programNode = AVAudioPlayerNode()
    private var programRing: ProgramAudioRingBuffer?
    private var trackLeftChannel: Int?
    private var trackRightChannel: Int?
    private var outstandingProgramBuffers = 0
    /// Frames per program buffer — kept equal to the LTC buffer length so the two
    /// pumps stay in step.
    private var programFramesPerBuffer = 0

    /// Buffers handed to `playerNode` that haven't reported completion yet — the
    /// current lead. `topUpBuffers` schedules until this reaches `primeCount`.
    private var outstandingBuffers = 0
    /// Bumped on every rebuild / `stop` / `update`. Completion handlers capture
    /// the generation they were scheduled under and ignore themselves once it's
    /// stale, so a superseded schedule's late completions don't skew the count.
    private var pumpGeneration = 0
    /// Periodically calls `topUpBuffers` on the main queue — a refill path that
    /// doesn't depend on the completion-handler chain being serviced promptly, so
    /// a brief main-actor stall can't drain the player-node queue.
    private var refillTimer: DispatchSourceTimer?

    /// What `start` was last told — used to rebuild after a config change.
    private var pendingStart: (timecode: Timecode, routing: LTCRoutingSettings)?
    private var configObserver: NSObjectProtocol?

    /// The sample rate of the active engine connection (the routed device's
    /// rate), or `nil` when not running — `LTCOutputHost` matches the program tap
    /// to it.
    var currentRenderSampleRate: Double? { renderFormat?.sampleRate }

    init() {
        engine.attach(playerNode)
        engine.attach(programNode)
        engine.attach(mixerNode)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        refillTimer?.cancel()
    }

    // MARK: - Transport hooks

    /// Begin (or restart) LTC output at `timecode`, on the device + channel the
    /// `routing` specifies. If `programRing` is non-nil and the routing assigns
    /// Track channels, the engine also plays whatever is pushed into it onto
    /// those channels. A no-op with a recorded error if `routing` has no LTC
    /// channel.
    func start(at timecode: Timecode, routing: LTCRoutingSettings, programRing: ProgramAudioRingBuffer? = nil) {
        guard routing.ltcChannel != nil else {
            lastError = "No output channel is assigned to LTC."
            return
        }
        pendingStart = (timecode, routing)
        self.programRing = programRing
        restartEngine()
    }

    /// Stop LTC output and release the device.
    func stop() {
        pumpGeneration += 1
        stopRefillTimer()
        playerNode.stop()
        programNode.stop()
        engine.stop()
        engine.reset()
        schedule = nil
        renderFormat = nil
        pendingStart = nil
        outstandingBuffers = 0
        outstandingProgramBuffers = 0
        programRing = nil
        trackLeftChannel = nil
        trackRightChannel = nil
        isRunning = false
    }

    /// Move the LTC stream to `timecode` (e.g. after a seek). Re-cues on the
    /// existing engine/connection — no device reconfigure or reconnect — so a
    /// scrub is a short re-prime, not a full restart. No-op if not running.
    func update(at timecode: Timecode) {
        guard isRunning, let pending = pendingStart, let format = renderFormat else { return }
        pumpGeneration += 1
        outstandingBuffers = 0
        outstandingProgramBuffers = 0
        pendingStart = (timecode, pending.routing)
        playerNode.stop()
        programNode.stop()
        programRing?.flush()
        let framesPerBuffer = LTCSchedule.framesPerBuffer(forTargetSeconds: bufferTargetSeconds, rate: timecode.rate)
        schedule = LTCSchedule(startTimecode: timecode, sampleRate: format.sampleRate, framesPerBuffer: framesPerBuffer)
        playerNode.play()
        programNode.play()
        topUpBuffers()
        topUpProgramBuffers()
    }

    // MARK: - Engine lifecycle

    private func handleConfigurationChange() {
        guard isRunning else { return }
        restartEngine()
    }

    private func restartEngine() {
        guard let pending = pendingStart else { return }
        pumpGeneration += 1
        stopRefillTimer()
        playerNode.stop()
        programNode.stop()
        engine.stop()
        engine.reset()
        outstandingBuffers = 0
        outstandingProgramBuffers = 0
        isRunning = false
        lastError = nil

        do {
            try configureDevice(uid: pending.routing.deviceUID)
            let outputFormat = engine.outputNode.outputFormat(forBus: 0)
            guard let renderFormat = Self.renderFormat(
                channelCount: max(1, Int(outputFormat.channelCount)),
                sampleRate: outputFormat.sampleRate
            ) else {
                throw LTCAudioOutputError.unsupportedOutputFormat
            }
            engine.connect(playerNode, to: mixerNode, format: renderFormat)
            engine.connect(programNode, to: mixerNode, format: renderFormat)
            engine.connect(mixerNode, to: engine.outputNode, format: renderFormat)
            self.renderFormat = renderFormat
            ltcChannel = pending.routing.ltcChannel ?? 0
            trackLeftChannel = pending.routing.trackLeftChannel
            trackRightChannel = pending.routing.trackRightChannel

            let framesPerBuffer = LTCSchedule.framesPerBuffer(
                forTargetSeconds: bufferTargetSeconds, rate: pending.timecode.rate
            )
            programFramesPerBuffer = framesPerBuffer
            schedule = LTCSchedule(
                startTimecode: pending.timecode,
                sampleRate: renderFormat.sampleRate,
                framesPerBuffer: framesPerBuffer
            )

            try engine.start()
            playerNode.play()
            programNode.play()
            topUpBuffers()
            topUpProgramBuffers()
            startRefillTimer()
            isRunning = true
        } catch {
            schedule = nil
            isRunning = false
            lastError = (error as? LTCAudioOutputError)?.description ?? error.localizedDescription
        }
    }

    private func configureDevice(uid: String?) throws {
        guard let uid else { return }   // nil → follow the system default output
        guard let device = AudioOutputDeviceList.device(forUID: uid) else {
            throw LTCAudioOutputError.deviceUnavailable
        }
        guard let outputUnit = engine.outputNode.audioUnit else {
            throw LTCAudioOutputError.unsupportedOutputFormat
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw LTCAudioOutputError.deviceUnavailable }
    }

    // MARK: - Buffer pump

    /// Schedule buffers until the player-node lead reaches `primeCount`. Called
    /// from priming, from each buffer's completion handler, and from the refill
    /// timer — whichever notices the lead is short first.
    private func topUpBuffers() {
        guard isRunningOrPriming else { return }
        let needed = Self.buffersToSchedule(outstanding: outstandingBuffers, target: primeCount)
        for _ in 0..<needed { scheduleOneBuffer() }
    }

    private func scheduleOneBuffer() {
        guard isRunningOrPriming, let format = renderFormat, var currentSchedule = schedule else { return }
        let buffer = currentSchedule.nextBuffer()
        schedule = currentSchedule
        let samples = Self.mutedSamples(buffer.samples, isMuted: isLTCMuted)
        guard let pcm = Self.makeBuffer(monoSamples: samples, format: format, channel: ltcChannel) else { return }
        outstandingBuffers += 1
        let generation = pumpGeneration
        // `AVAudioPlayerNode` invokes this on an internal engine thread, not the
        // main queue — hop to the main actor (a bare `assumeIsolated` would trap).
        playerNode.scheduleBuffer(pcm) { [weak self] in
            Task { @MainActor in self?.bufferDidComplete(generation: generation) }
        }
    }

    private func bufferDidComplete(generation: Int) {
        guard generation == pumpGeneration else { return }   // a superseded schedule's late completion
        outstandingBuffers = max(0, outstandingBuffers - 1)
        topUpBuffers()
    }

    /// `true` while we should keep the pipeline topped up — either fully running,
    /// or in the priming burst right before `isRunning` flips true.
    private var isRunningOrPriming: Bool { schedule != nil && engine.isRunning }

    // MARK: - Refill timer

    private func startRefillTimer() {
        stopRefillTimer()
        let interval = bufferTargetSeconds / 2
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.topUpBuffers()
                self?.topUpProgramBuffers()
            }
        }
        refillTimer = timer
        timer.resume()
    }

    private func stopRefillTimer() {
        refillTimer?.cancel()
        refillTimer = nil
    }

    /// Toggle whether the LTC channel emits silence on the next render block.
    /// The encoder keeps running. Idempotent.
    func setLTCMuted(_ muted: Bool) {
        isLTCMuted = muted
    }
}

// MARK: - Program-audio pump

extension LTCAudioOutput {

    /// Whether program (track) audio should be scheduled — there is a source ring
    /// buffer and the routing assigns at least one Track channel.
    private var hasProgramOutput: Bool {
        programRing != nil && (trackLeftChannel != nil || trackRightChannel != nil) && programFramesPerBuffer > 0
    }

    func topUpProgramBuffers() {
        guard isRunningOrPriming, hasProgramOutput else { return }
        let needed = Self.buffersToSchedule(outstanding: outstandingProgramBuffers, target: primeCount)
        for _ in 0..<needed { scheduleOneProgramBuffer() }
    }

    private func scheduleOneProgramBuffer() {
        guard isRunningOrPriming, hasProgramOutput, let format = renderFormat, let ring = programRing else { return }
        let interleaved = ring.drain(frameCount: programFramesPerBuffer)   // always full length, zero-padded
        var left = [Float](repeating: 0, count: programFramesPerBuffer)
        var right = [Float](repeating: 0, count: programFramesPerBuffer)
        for frame in 0..<programFramesPerBuffer {
            left[frame] = interleaved[frame * 2]
            right[frame] = interleaved[frame * 2 + 1]
        }
        var entries: [(samples: [Float], channel: Int)] = []
        if let leftCh = trackLeftChannel { entries.append((left, leftCh)) }
        if let rightCh = trackRightChannel { entries.append((right, rightCh)) }
        guard !entries.isEmpty, let pcm = Self.makeBuffer(channels: entries, format: format) else { return }
        outstandingProgramBuffers += 1
        let generation = pumpGeneration
        programNode.scheduleBuffer(pcm) { [weak self] in
            Task { @MainActor in self?.programBufferDidComplete(generation: generation) }
        }
    }

    private func programBufferDidComplete(generation: Int) {
        guard generation == pumpGeneration else { return }
        outstandingProgramBuffers = max(0, outstandingProgramBuffers - 1)
        topUpProgramBuffers()
    }
}

enum LTCAudioOutputError: Error, CustomStringConvertible {
    case deviceUnavailable
    case unsupportedOutputFormat

    var description: String {
        switch self {
        case .deviceUnavailable: "The selected audio output device is unavailable."
        case .unsupportedOutputFormat: "The audio output device's format isn't supported."
        }
    }
}
