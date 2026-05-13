import SwiftUI

/// The layered overlays drawn on top of the waveform inside `WaveformContainer`'s
/// scroll content — the cue markers and (when `View → Show Tempo Grid` is on) the
/// beat/bar grid. Split out so `WaveformContainer.swift` stays under the
/// `type_body_length` cap.
extension WaveformContainer {

    /// The beat/bar grid behind the cue markers — shown only when the toggle is on,
    /// the audio's duration is known, and the active item actually has a tempo map.
    @ViewBuilder
    func tempoGridOverlay() -> some View {
        if showTempoGrid, loadedDuration > 0, !tempoMap.sections.isEmpty {
            TempoGridOverlay(tempoMap: tempoMap, duration: loadedDuration)
        }
    }

    @ViewBuilder
    func markersOverlay() -> some View {
        if loadedDuration > 0 {
            CueMarkersOverlay(
                cues: cues,
                duration: loadedDuration,
                resolveColorHex: resolveColorHex,
                selectedCueIDs: selectedCueIDs,
                onSelectCue: onSelectCue,
                onToggleCue: onToggleCue,
                onSeek: onSeek,
                onRetime: onRetime
            )
        }
    }
}
