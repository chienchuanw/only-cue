import AVFoundation
import MediaToolbox

/// Mutable state shared between a `ProgramAudioTap` and its C callbacks via the
/// tap's storage pointer. File-scoped so the callback free functions below can
/// reach it.
private final class ProgramTapContext {
    let ring: ProgramAudioRingBuffer
    let renderSampleRate: Double
    var converter: AVAudioConverter?
    var sourceFormat: AVAudioFormat?
    var outputFormat: AVAudioFormat?

    init(ring: ProgramAudioRingBuffer, renderSampleRate: Double) {
        self.ring = ring
        self.renderSampleRate = renderSampleRate
    }
}

/// Siphons an `AVPlayerItem`'s program audio via an `MTAudioProcessingTap`,
/// resamples it to a stereo interleaved Float32 stream at the LTC engine's render
/// sample rate, and pushes it into a `ProgramAudioRingBuffer` for `LTCAudioOutput`
/// to play onto the Track L / Track R channels. While a tap is attached the host
/// (`LTCOutputHost`) also mutes `AVPlayer` directly, so this is the only path the
/// program audio takes.
///
/// Not headless-testable — it needs a live, rendering `AVPlayerItem`. Verified by
/// running the app. The realtime `process` callback only converts and pushes
/// (with a brief unfair-lock hold inside the ring buffer); the converter and its
/// output buffer are created once per `prepare`.
@MainActor
final class ProgramAudioTap {

    private let ring: ProgramAudioRingBuffer
    private let renderSampleRate: Double
    private weak var item: AVPlayerItem?
    private var tap: MTAudioProcessingTap?

    init(ring: ProgramAudioRingBuffer, renderSampleRate: Double) {
        self.ring = ring
        self.renderSampleRate = renderSampleRate > 0 ? renderSampleRate : 48_000
    }

    /// Install the tap onto `item`'s first audio track. No-op if the item has no
    /// audio track or the tap can't be created. Replaces any tap this object
    /// previously attached. Async because the asset's track list is loaded
    /// asynchronously (synchronous `tracks(withMediaType:)` is deprecated and can
    /// raise on macOS 13+).
    func attach(to item: AVPlayerItem) async {
        detach()
        let audioTracks = try? await item.asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks?.first else { return }

        let context = ProgramTapContext(ring: ring, renderSampleRate: renderSampleRate)
        let clientInfo = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: programTapInit,
            finalize: programTapFinalize,
            prepare: programTapPrepare,
            unprepare: programTapUnprepare,
            process: programTapProcess
        )

        var tapOut: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tapOut
        )
        guard status == noErr, let createdTap = tapOut else {
            Unmanaged<ProgramTapContext>.fromOpaque(clientInfo).release()
            return
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = createdTap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix

        tap = createdTap
        self.item = item
    }

    /// Remove the tap from the item and release it (the retained context is freed
    /// by the tap's `finalize` callback). Flushes the ring buffer.
    func detach() {
        item?.audioMix = nil
        item = nil
        tap = nil
        ring.flush()
    }
}

// MARK: - C callbacks (free functions so the C-function-pointer conversion works)

private func tapContext(_ tap: MTAudioProcessingTap) -> ProgramTapContext {
    Unmanaged<ProgramTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private func programTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func programTapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<ProgramTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func programTapPrepare(
    _ tap: MTAudioProcessingTap, _ maxFrames: CMItemCount, _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let context = tapContext(tap)
    guard let source = AVAudioFormat(streamDescription: processingFormat) else { return }
    guard let output = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: context.renderSampleRate,
        channels: 2,
        interleaved: true
    ) else { return }
    context.sourceFormat = source
    context.outputFormat = output
    context.converter = AVAudioConverter(from: source, to: output)
}

private func programTapUnprepare(_ tap: MTAudioProcessingTap) {
    let context = tapContext(tap)
    context.converter = nil
    context.sourceFormat = nil
    context.outputFormat = nil
}

// swiftlint:disable:next function_parameter_count
private func programTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let context = tapContext(tap)
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr,
          numberFramesOut.pointee > 0,
          let source = context.sourceFormat,
          let output = context.outputFormat,
          let converter = context.converter,
          let inBuffer = AVAudioPCMBuffer(pcmFormat: source, bufferListNoCopy: bufferListInOut)
    else { return }
    inBuffer.frameLength = AVAudioFrameCount(numberFramesOut.pointee)

    let outCapacity = AVAudioFrameCount(
        (Double(inBuffer.frameLength) * output.sampleRate / source.sampleRate).rounded(.up)
    ) + 16
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: outCapacity) else { return }

    var fed = false
    var conversionError: NSError?
    converter.convert(to: outBuffer, error: &conversionError) { _, statusOut in
        if fed { statusOut.pointee = .noDataNow; return nil }
        fed = true
        statusOut.pointee = .haveData
        return inBuffer
    }
    guard conversionError == nil, outBuffer.frameLength > 0,
          let interleaved = outBuffer.floatChannelData?[0] else { return }
    let sampleCount = Int(outBuffer.frameLength) * 2   // interleaved stereo
    context.ring.push(interleavedStereo: Array(UnsafeBufferPointer(start: interleaved, count: sampleCount)))
}
