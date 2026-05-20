import SwiftUI

/// The layered overlays drawn on top of the waveform inside `WaveformContainer`'s
/// scroll content — the cue markers and (when `View → Show Tempo Grid` is on) the
/// beat/bar grid. Split out so `WaveformContainer.swift` stays under the
/// `type_body_length` cap.
extension WaveformContainer {

    /// The beat/bar grid behind the cue markers — shown only when the toggle is on,
    /// the audio's duration is known, and the active item actually has BPM cues.
    @ViewBuilder
    func tempoGridOverlay() -> some View {
        if showTempoGrid, loadedDuration > 0, !tempoGrid.isEmpty {
            TempoGridOverlay(grid: tempoGrid, duration: loadedDuration)
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
                tempoGrid: tempoGrid,
                onSelectCue: onSelectCue,
                onToggleCue: onToggleCue,
                onSeek: onSeek,
                onRetime: onRetime,
                onNudge: onNudge,
                isEditable: editorMode.cueMarkersEditable
            )
        }
    }

    /// The lyric lane band pinned to the bottom of the waveform content — shown
    /// only when `View → Show Lyrics Lane` is on, the duration is known, and the
    /// active item has lyrics. Lives in the zoomable scroll content, so it
    /// inherits horizontal zoom.
    @ViewBuilder
    func lyricsLaneOverlay() -> some View {
        if showLyricsLane, loadedDuration > 0, !lyrics.lines.isEmpty {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LyricsLaneView(lyrics: lyrics, duration: loadedDuration, onSeek: onSeekToLyric)
            }
        }
    }
}
