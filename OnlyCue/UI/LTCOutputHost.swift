import AVFoundation
import SwiftUI

/// Drives an `LTCAudioOutput` from the document window's transport: starts LTC on
/// play (at the playhead's timecode, per `ProjectModel.timecodeSettings` and
/// `LTCRoutingStore`), stops on pause, re-cues on a seek, and restarts when the
/// routing or timecode settings change mid-playback. A no-op unless LTC is
/// enabled and a channel is assigned to it (`LTCRoutingSettings.isComplete`).
///
/// When the routing assigns Track L / R channels and a media item is loaded, it
/// also mutes `AVPlayer`'s own audio output and installs a `ProgramAudioTap` so
/// the media's program audio is replayed through the LTC engine onto those
/// channels — the routed device then carries only what the engine produces, never
/// a sum of LTC and program audio. Mirrors the `.exportSheet` / `.oscServerHost`
/// host-modifier pattern so `DocumentView`'s body stays under the
/// `type_body_length` cap.
///
/// Attached via `.ltcOutput(engine:document:)`.
private struct LTCOutputHost: ViewModifier {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    @ObservedObject private var routingStore = LTCRoutingStore.shared
    @StateObject private var output = LTCAudioOutput()

    /// Reused for the host's lifetime — the tap pushes into it, `LTCAudioOutput`
    /// drains it. ~1 s of stereo @ 48 kHz, comfortably above the engine's
    /// `primeCount` lead. `@State` so it survives view-struct recreations.
    @State private var programRing = ProgramAudioRingBuffer(capacityFrames: 48_000)
    @State private var programTap: ProgramAudioTap?

    /// A `currentTime` jump larger than this between observations is treated as a
    /// seek (normal playback advances ~0.1 s per tick).
    private let seekThreshold: TimeInterval = 1.0

    private var timecodeSettings: ProjectTimecodeSettings { document.model.timecodeSettings }

    func body(content: Content) -> some View {
        content
            .onChange(of: engine.isPlaying) { _, playing in
                refresh(playing: playing)
            }
            .onChange(of: engine.currentTime) { oldValue, newValue in
                if output.isRunning, abs(newValue - oldValue) > seekThreshold {
                    output.update(at: timecodeSettings.timecode(atPlaybackSeconds: newValue))
                }
            }
            .onChange(of: routingStore.settings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: timecodeSettings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onDisappear { teardown() }
    }

    private func refresh(playing: Bool) {
        guard playing, routingStore.settings.isComplete else {
            teardown()
            return
        }
        let routing = routingStore.settings
        let wantsProgramAudio = routing.hasTrackChannels && engine.player.currentItem != nil
        output.start(
            at: timecodeSettings.timecode(atPlaybackSeconds: engine.currentTime),
            routing: routing,
            programRing: wantsProgramAudio ? programRing : nil
        )
        if wantsProgramAudio, output.isRunning, let item = engine.player.currentItem {
            installTap(on: item)
            engine.setAudioMuted(true)
        } else {
            removeTap()
            engine.setAudioMuted(false)
        }
    }

    private func installTap(on item: AVPlayerItem) {
        removeTap()
        let tap = ProgramAudioTap(ring: programRing, renderSampleRate: output.currentRenderSampleRate ?? 48_000)
        programTap = tap
        Task { @MainActor in
            // Bail if a teardown/replace happened while the asset's tracks loaded.
            guard programTap === tap else { return }
            await tap.attach(to: item)
        }
    }

    private func removeTap() {
        programTap?.detach()
        programTap = nil
    }

    private func teardown() {
        output.stop()
        removeTap()
        engine.setAudioMuted(false)
    }
}

extension View {
    func ltcOutput(engine: PlayerEngine, document: CueListDocument) -> some View {
        modifier(LTCOutputHost(engine: engine, document: document))
    }
}
