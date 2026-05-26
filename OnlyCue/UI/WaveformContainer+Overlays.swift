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
                isEditable: editorMode.cueMarkersEditable,
                // Only Lyric mode dims markers (lyric ribbons are the active
                // surface). Show mode keeps markers solid; the waveform peaks
                // below are dimmed instead. Audit §9.1.
                isDimmed: editorMode == .lyric
            )
        }
    }

    /// The lyric lane pinned to the bottom of the waveform content. Shown in
    /// Lyric mode always (the editing surface), and in Cue / Show modes when the
    /// item has at least one placed line. Lives in the zoomable scroll content,
    /// so it inherits horizontal zoom.
    @ViewBuilder
    func lyricsLaneOverlay() -> some View {
        let hasPlaced = !lyrics.placedLines.isEmpty
        if loadedDuration > 0, editorMode.lyricsEditable || hasPlaced {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LyricsLaneView(
                    lyrics: lyrics,
                    duration: loadedDuration,
                    editorMode: editorMode,
                    onSeek: onSeekToLyric,
                    onRetime: onRetimeLyric,
                    onUnplace: onUnplaceLyric,
                    onDelete: onDeleteLyric,
                    ghostLine: ghostLyricLine,
                    onPlaceAtMediaTime: onPlaceLyricAtMediaTime
                )
            }
        }
    }
}
