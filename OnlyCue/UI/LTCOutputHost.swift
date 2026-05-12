import SwiftUI

/// Drives an `LTCAudioOutput` from the document window's transport: starts LTC
/// on play (at the playhead's timecode, per `ProjectModel.timecodeSettings` and
/// `LTCRoutingStore`), stops on pause, re-cues on a seek, and restarts when the
/// routing or timecode settings change mid-playback. A no-op when no output
/// channel is assigned to LTC. Mirrors the `.exportSheet` / `.oscServerHost`
/// host-modifier pattern so `DocumentView`'s body stays under the
/// `type_body_length` cap.
///
/// Attached via `.ltcOutput(engine:document:)`.
private struct LTCOutputHost: ViewModifier {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    @ObservedObject private var routingStore = LTCRoutingStore.shared
    @StateObject private var output = LTCAudioOutput()

    /// A `currentTime` jump larger than this between observations is treated as a
    /// seek (normal playback advances ~0.1 s per tick).
    private let seekThreshold: TimeInterval = 1.0

    private var settings: ProjectTimecodeSettings { document.model.timecodeSettings }

    func body(content: Content) -> some View {
        content
            .onChange(of: engine.isPlaying) { _, playing in
                refresh(playing: playing)
            }
            .onChange(of: engine.currentTime) { oldValue, newValue in
                if output.isRunning, abs(newValue - oldValue) > seekThreshold {
                    output.update(at: settings.timecode(atPlaybackSeconds: newValue))
                }
            }
            .onChange(of: routingStore.settings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onChange(of: settings) { _, _ in
                refresh(playing: engine.isPlaying)
            }
            .onDisappear { output.stop() }
    }

    private func refresh(playing: Bool) {
        guard playing, routingStore.settings.isComplete else {
            output.stop()
            return
        }
        output.start(at: settings.timecode(atPlaybackSeconds: engine.currentTime), routing: routingStore.settings)
    }
}

extension View {
    func ltcOutput(engine: PlayerEngine, document: CueListDocument) -> some View {
        modifier(LTCOutputHost(engine: engine, document: document))
    }
}
