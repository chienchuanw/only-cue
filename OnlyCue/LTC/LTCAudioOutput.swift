import AVFoundation
import CoreAudio

/// Renders a continuous LTC signal onto a chosen Core Audio output device — the
/// `AVAudioEngine` half of epic #33's generator. Given the timecode at the
/// current playhead, the project framerate, and `LTCRoutingSettings`, it opens
/// an engine on the routed device and streams `LTCSchedule` buffers onto an
/// `AVAudioPlayerNode`, with the mono LTC placed on the channel the routing
/// assigned (`ChannelRole.ltc`) and silence on the others. Rebuilds on
/// `AVAudioEngineConfigurationChange` (device disconnect / sample-rate change)
/// from the timecode it was last told.
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
    private var schedule: LTCSchedule?
    /// Render format + LTC channel of the active engine connection — set by
    /// `restartEngine`, read by `scheduleOneBuffer` (so the off-thread completion
    /// handler hops back to `self` rather than capturing them across the actor).
    private var renderFormat: AVAudioFormat?
    private var ltcChannel = 0

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

    init() {
        engine.attach(playerNode)
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
    /// `routing` specifies. A no-op with a recorded error if `routing` has no
    /// LTC channel.
    func start(at timecode: Timecode, routing: LTCRoutingSettings) {
        guard routing.ltcChannel != nil else {
            lastError = "No output channel is assigned to LTC."
            return
        }
        pendingStart = (timecode, routing)
        restartEngine()
    }

    /// Stop LTC output and release the device.
    func stop() {
        pumpGeneration += 1
        stopRefillTimer()
        playerNode.stop()
        engine.stop()
        engine.reset()
        schedule = nil
        renderFormat = nil
        pendingStart = nil
        outstandingBuffers = 0
        isRunning = false
    }

    /// Move the LTC stream to `timecode` (e.g. after a seek). Re-cues on the
    /// existing engine/connection — no device reconfigure or reconnect — so a
    /// scrub is a short re-prime, not a full restart. No-op if not running.
    func update(at timecode: Timecode) {
        guard isRunning, let pending = pendingStart, let format = renderFormat else { return }
        pumpGeneration += 1
        outstandingBuffers = 0
        pendingStart = (timecode, pending.routing)
        playerNode.stop()
        let framesPerBuffer = LTCSchedule.framesPerBuffer(forTargetSeconds: bufferTargetSeconds, rate: timecode.rate)
        schedule = LTCSchedule(startTimecode: timecode, sampleRate: format.sampleRate, framesPerBuffer: framesPerBuffer)
        playerNode.play()
        topUpBuffers()
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
        engine.stop()
        engine.reset()
        outstandingBuffers = 0
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
            engine.connect(playerNode, to: engine.outputNode, format: renderFormat)
            self.renderFormat = renderFormat
            ltcChannel = pending.routing.ltcChannel ?? 0

            let framesPerBuffer = LTCSchedule.framesPerBuffer(
                forTargetSeconds: bufferTargetSeconds, rate: pending.timecode.rate
            )
            schedule = LTCSchedule(
                startTimecode: pending.timecode,
                sampleRate: renderFormat.sampleRate,
                framesPerBuffer: framesPerBuffer
            )

            try engine.start()
            playerNode.play()
            topUpBuffers()
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
        guard let pcm = Self.makeBuffer(monoSamples: buffer.samples, format: format, channel: ltcChannel) else { return }
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
            MainActor.assumeIsolated { self?.topUpBuffers() }
        }
        refillTimer = timer
        timer.resume()
    }

    private func stopRefillTimer() {
        refillTimer?.cancel()
        refillTimer = nil
    }

    /// How many more buffers to schedule to reach `target` given the current
    /// `outstanding` lead. Pure — exposed for tests.
    static func buffersToSchedule(outstanding: Int, target: Int) -> Int {
        max(0, target - max(0, outstanding))
    }

    /// A deinterleaved 32-bit-float format with `channelCount` channels in a
    /// discrete (non-standard) layout — `AVAudioFormat`'s simple initializers
    /// refuse channel counts without a standard `AVAudioChannelLayout` (3, 5, …),
    /// so use an explicit discrete layout. `nil` only for `channelCount < 1`.
    static func renderFormat(channelCount: Int, sampleRate: Double) -> AVAudioFormat? {
        guard channelCount >= 1, sampleRate > 0 else { return nil }
        guard let layout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelCount)
        ) else { return nil }
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout
        )
    }

    /// Build a multichannel float PCM buffer carrying `monoSamples` on `channel`
    /// and silence on every other channel of `format`. Out-of-range `channel`
    /// clamps into bounds. Pure — exposed for tests.
    static func makeBuffer(monoSamples: [Float], format: AVAudioFormat, channel: Int) -> AVAudioPCMBuffer? {
        guard !monoSamples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(monoSamples.count)),
              let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(monoSamples.count)
        let channelCount = Int(format.channelCount)
        let target = min(max(0, channel), channelCount - 1)
        for index in 0..<channelCount {
            let destination = channels[index]
            if index == target {
                monoSamples.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress { destination.update(from: base, count: monoSamples.count) }
                }
            } else {
                destination.update(repeating: 0, count: monoSamples.count)
            }
        }
        return buffer
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
