import AVFoundation
import MediaToolbox

/// Mutable state shared between a `MusicOnlyTap` and its C callbacks via the
/// tap's storage pointer. File-scoped so the callback free functions below can
/// reach it.
private final class MusicOnlyTapContext {
    let ltcChannel: Int
    var sourceFormat: AVAudioFormat?

    init(ltcChannel: Int) {
        self.ltcChannel = ltcChannel
    }
}

/// Silences the striped-LTC channel of an `AVPlayerItem`'s program audio and
/// centers the surviving music onto every channel, IN PLACE, so plain `AVPlayer`
/// playback carries only the music. This is the *music-only* mode of the plain
/// (non-LTC-output) playback path; the host (`LTCOutputHost`) installs it only
/// when a clip has striped LTC and its per-clip mode is music-only.
///
/// Simpler than `ProgramAudioTap`: no ring buffer, no `AVAudioConverter`. It
/// mutates the source buffers the tap already holds and lets `AVPlayer` render
/// them — it is a filter, not a siphon. The two taps are mutually exclusive:
/// only one is ever on `item.audioMix`.
///
/// Not headless-testable — it needs a live, rendering `AVPlayerItem`. Verified by
/// building/running the app. The sample maths is unit-tested in `MusicOnlyMixer`.
@MainActor
final class MusicOnlyTap {

    let ltcChannel: Int
    /// The item this tap is currently attached to (nil before `attach` completes
    /// or after `detach`). The host reads it to keep `installMusicOnlyTap`
    /// idempotent across refreshes without re-attaching to a *different* item.
    private(set) weak var attachedItem: AVPlayerItem?
    private var tap: MTAudioProcessingTap?

    init(ltcChannel: Int) {
        self.ltcChannel = ltcChannel
    }

    /// Install the tap onto `item`'s first audio track. No-op if the item has no
    /// audio track or the tap can't be created. Replaces any tap this object
    /// previously attached. Async because the asset's track list is loaded
    /// asynchronously (synchronous `tracks(withMediaType:)` is deprecated and can
    /// raise on macOS 13+). Mirrors `ProgramAudioTap.attach`.
    func attach(to item: AVPlayerItem) async {
        detach()
        let audioTracks = try? await item.asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks?.first else { return }

        let context = MusicOnlyTapContext(ltcChannel: ltcChannel)
        let clientInfo = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: musicOnlyTapInit,
            finalize: musicOnlyTapFinalize,
            prepare: musicOnlyTapPrepare,
            unprepare: musicOnlyTapUnprepare,
            process: musicOnlyTapProcess
        )

        var tapOut: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tapOut
        )
        guard status == noErr, let createdTap = tapOut else {
            Unmanaged<MusicOnlyTapContext>.fromOpaque(clientInfo).release()
            return
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = createdTap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix

        tap = createdTap
        self.attachedItem = item
    }

    /// Remove the tap from the item and release it (the retained context is freed
    /// by the tap's `finalize` callback). Mirrors `ProgramAudioTap.detach`.
    func detach() {
        attachedItem?.audioMix = nil
        attachedItem = nil
        tap = nil
    }
}

// MARK: - C callbacks (free functions so the C-function-pointer conversion works)

private func musicOnlyTapContext(_ tap: MTAudioProcessingTap) -> MusicOnlyTapContext {
    Unmanaged<MusicOnlyTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private func musicOnlyTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func musicOnlyTapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<MusicOnlyTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func musicOnlyTapPrepare(
    _ tap: MTAudioProcessingTap, _ maxFrames: CMItemCount, _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let context = musicOnlyTapContext(tap)
    context.sourceFormat = AVAudioFormat(streamDescription: processingFormat)
}

private func musicOnlyTapUnprepare(_ tap: MTAudioProcessingTap) {
    musicOnlyTapContext(tap).sourceFormat = nil
}

// swiftlint:disable:next function_parameter_count
private func musicOnlyTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let context = musicOnlyTapContext(tap)
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr,
          numberFramesOut.pointee > 0,
          let source = context.sourceFormat,
          let buffer = AVAudioPCMBuffer(pcmFormat: source, bufferListNoCopy: bufferListInOut)
    else { return }
    buffer.frameLength = AVAudioFrameCount(numberFramesOut.pointee)

    // Shared, unit-tested transform (`MusicOnlyMixerBufferTests`). Its own guards
    // no-op on mono / out-of-range LTC index, so the tap needs no extra gating.
    MusicOnlyMixer.applyInPlace(to: buffer, excludingChannel: context.ltcChannel)
}
