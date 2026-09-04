import SwiftUI

/// Drives an `MTCOutput` from the document window's transport: starts MIDI
/// Timecode on play (at the playhead's timecode, per `ProjectModel.timecodeSettings`
/// and `MTCOutputStore`), stops on pause, re-anchors on a seek, and locates the
/// receiver when the playhead moves while paused. A no-op unless MTC is enabled
/// and a destination is selected (`MTCOutputSettings.isComplete`).
///
/// The MTC twin of `LTCOutputHost`, and deliberately much smaller: there are no
/// audio taps, no channel roles and no program audio to re-route — a MIDI
/// destination has no channels, so the destination *is* the routing.
///
/// The timecode it feeds the generator comes from the same
/// `timecodeSettings.timecode(atPlaybackSeconds:forItem:)` call `LTCOutputHost`
/// makes, which is what makes "LTC and MTC always agree" structural rather than
/// aspirational (ADR-032).
///
/// Two behaviours differ from the LTC path on purpose:
///
/// - **Any** seek re-cues, not only one over 1.0 s (`MTCLocateGate`) — re-cueing
///   MTC costs a single Full Frame, where LTC costs a buffer re-prime.
/// - The playhead is followed **while paused** too, so a console parked on a cue
///   shows the right time before the operator hits go. Only a Full Frame goes
///   out then; the quarter-frame stream stays stopped, because a stalled stream
///   is non-standard and can read as a broken master.
///
/// Attached via `.mtcOutput(engine:document:)`.
private struct MTCOutputHost: ViewModifier {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    @ObservedObject private var store = MTCOutputStore.shared
    @StateObject private var output = MTCOutput()

    /// When the last locate went out, for `MTCLocateGate`'s throttle. `@State` so
    /// it survives view-struct recreations.
    @State private var lastLocateAt: TimeInterval?

    private var timecodeSettings: ProjectTimecodeSettings { document.model.timecodeSettings }

    func body(content: Content) -> some View {
        content
            // Published so `MTCStatusPill` can read the generator without the
            // object being threaded through ModeAwareInspector and CueListPane.
            .environment(\.mtcOutput, output)
            .onChange(of: engine.isPlaying) { _, playing in
                refresh(playing: playing)
            }
            .onChange(of: engine.currentTime) { oldValue, newValue in
                handlePlayheadMove(from: oldValue, to: newValue)
            }
            .onChange(of: store.settings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: timecodeSettings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: document.model.activeItem?.id) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onDisappear { output.stop() }
    }

    // MARK: - Transport

    /// The single decision point for whether the generator runs.
    private func refresh(playing: Bool) {
        let settings = store.settings
        guard settings.isComplete, let item = document.model.activeItem else {
            output.stop()
            return
        }
        let timecode = timecodeSettings.timecode(atPlaybackSeconds: engine.currentTime, forItem: item)
        if playing {
            output.start(at: timecode, destinationUID: settings.destinationUID)
        } else {
            output.stop()
            sendLocate(timecode, destinationUID: settings.destinationUID)
        }
    }

    private func handlePlayheadMove(from oldValue: TimeInterval, to newValue: TimeInterval) {
        let settings = store.settings
        guard settings.isComplete, let item = document.model.activeItem else { return }
        let timecode = timecodeSettings.timecode(atPlaybackSeconds: newValue, forItem: item)

        if engine.isPlaying {
            guard output.isRunning, MTCLocateGate.isSeekWhilePlaying(from: oldValue, to: newValue) else { return }
            output.update(at: timecode)
        } else {
            guard MTCLocateGate.isLocateWhilePaused(from: oldValue, to: newValue) else { return }
            sendLocate(timecode, destinationUID: settings.destinationUID)
        }
    }

    /// Locate the receiver while stopped, throttled so scrubbing the waveform
    /// cannot flood the port.
    private func sendLocate(_ timecode: Timecode, destinationUID: String?) {
        let now = Date.timeIntervalSinceReferenceDate
        guard MTCLocateGate.shouldSend(now: now, lastSentAt: lastLocateAt) else { return }
        lastLocateAt = now
        output.locateWhileStopped(at: timecode, destinationUID: destinationUID)
    }
}

extension View {
    func mtcOutput(engine: PlayerEngine, document: CueListDocument) -> some View {
        modifier(MTCOutputHost(engine: engine, document: document))
    }
}
