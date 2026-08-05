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
/// It is also the single owner of the source-audio *music-only* tap on the plain
/// `AVPlayer` path: when a clip has striped LTC and its per-clip mode is
/// music-only (`playsOriginalSourceAudio == false`), and the program-audio tap is
/// NOT active, it installs a `MusicOnlyTap` to silence the LTC channel in place.
/// The two taps are mutually exclusive — at most one is ever on `item.audioMix`.
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

    /// The plain-path music-only tap and the active clip's striped-LTC track. The
    /// track is decoded via the shared cache (so it does not re-scan when
    /// `StripedTimecodeHost` already scanned the same clip).
    @State private var musicOnlyTap: MusicOnlyTap?
    @State private var stripedTrack: StripedTimecodeTrack?

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
                guard output.isRunning,
                      abs(newValue - oldValue) > seekThreshold,
                      let item = document.model.activeItem else { return }
                output.update(at: timecodeSettings.timecode(atPlaybackSeconds: newValue, forItem: item))
            }
            .onChange(of: routingStore.settings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: timecodeSettings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: document.model.activeItem?.ltcMuted ?? false) { _, newMuted in
                output.setLTCMuted(newMuted)
            }
            .task(id: document.model.activeItem?.id) {
                // Decode the active clip's striped LTC (shared cache), mirroring
                // `StripedTimecodeHost`, then re-decide which tap to install.
                stripedTrack = nil
                let decoded = await MediaImporter.stripedTimecode(for: document.model.activeItem)
                guard !Task.isCancelled else { return }
                stripedTrack = decoded
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: document.model.activeItem?.playsOriginalSourceAudio ?? false) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: engine.player.currentItem) { _, _ in
                // Install the music-only tap when a clip loads even while paused:
                // `attach` is async, so gating it on play would leak LTC on the
                // first rendered frames.
                refresh(playing: engine.isPlaying)
            }
            .onDisappear { teardown() }
    }

    /// The single decision point for the LTC engine transport and for which of
    /// the two mutually-exclusive taps is on `item.audioMix`.
    private func refresh(playing: Bool) {
        let item = engine.player.currentItem
        let mediaItem = document.model.activeItem
        let routing = routingStore.settings
        let ltcOutputActive = playing && routing.isComplete && mediaItem != nil
        let wantsProgramAudio = ltcOutputActive && routing.hasTrackChannels && item != nil

        if ltcOutputActive, let mediaItem {
            output.start(
                at: timecodeSettings.timecode(atPlaybackSeconds: engine.currentTime, forItem: mediaItem),
                routing: routing,
                programRing: wantsProgramAudio ? programRing : nil
            )
            // Honour the active clip's persisted mute on fresh start (handles the
            // case where the clip began muted before play).
            output.setLTCMuted(mediaItem.ltcMuted)
        } else {
            output.stop()
        }

        if wantsProgramAudio, output.isRunning, let item {
            // Program-audio path: the LTC engine replays the program audio, so the
            // music-only source tap must yield the audioMix to `ProgramAudioTap`.
            removeMusicOnlyTap()
            installTap(on: item)
            engine.setAudioMuted(true)
        } else {
            removeTap()
            engine.setAudioMuted(false)
            // Plain path: mute the source LTC channel when the clip is music-only.
            if let item, let mediaItem, let track = stripedTrack,
               !mediaItem.playsOriginalSourceAudio {
                installMusicOnlyTap(on: item, ltcChannel: track.ltcChannel)
            } else {
                removeMusicOnlyTap()
            }
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

    /// Idempotent: leaves an already-attached tap for this same channel in place,
    /// so repeated refreshes don't thrash `item.audioMix`.
    private func installMusicOnlyTap(on item: AVPlayerItem, ltcChannel: Int) {
        if let existing = musicOnlyTap, existing.ltcChannel == ltcChannel, existing.attachedItem === item {
            return
        }
        removeMusicOnlyTap()
        let tap = MusicOnlyTap(ltcChannel: ltcChannel)
        musicOnlyTap = tap
        Task { @MainActor in
            // Bail if a teardown/replace happened while the asset's tracks loaded.
            guard musicOnlyTap === tap else { return }
            await tap.attach(to: item)
        }
    }

    private func removeMusicOnlyTap() {
        musicOnlyTap?.detach()
        musicOnlyTap = nil
    }

    private func teardown() {
        output.stop()
        removeTap()
        removeMusicOnlyTap()
        engine.setAudioMuted(false)
    }
}

extension View {
    func ltcOutput(engine: PlayerEngine, document: CueListDocument) -> some View {
        modifier(LTCOutputHost(engine: engine, document: document))
    }
}
