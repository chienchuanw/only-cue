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

    /// The mm:ss time-ruler pinned at the top of the waveform content (Figma
    /// `318:1271`): `border-strong` ticks (major taller) with `monoMicro`
    /// labels on the majors, sitting just below the cue-marker flags. Lives in
    /// the zoomable scroll content so it tracks zoom/scroll and stays aligned to
    /// the cues; non-interactive so click-to-seek and marker drags pass through.
    @ViewBuilder
    func timeRulerOverlay() -> some View {
        if loadedDuration > 0 {
            GeometryReader { proxy in
                Canvas { context, size in
                    drawTimeRuler(into: context, size: size)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .allowsHitTesting(false)
        }
    }

    private func drawTimeRuler(into context: GraphicsContext, size: CGSize) {
        guard loadedDuration > 0, size.width > 0 else { return }
        // Sit just under the cue-marker flag zone (flags occupy the top ~22pt).
        let topInset: CGFloat = 24
        let ticks = WaveformRulerTicks.ticks(duration: loadedDuration, contentWidth: size.width)
        let strokeColor = GraphicsContext.Shading.color(DS.Color.borderStrong)
        for tick in ticks {
            let tickHeight: CGFloat = tick.isMajor ? 8 : 4
            var path = Path()
            path.move(to: CGPoint(x: tick.x, y: topInset))
            path.addLine(to: CGPoint(x: tick.x, y: topInset + tickHeight))
            context.stroke(path, with: strokeColor, lineWidth: 1)
            guard tick.isMajor else { continue }
            let text = Text(tick.label)
                .font(DS.Text.monoMicro)
                .foregroundColor(DS.Color.textTertiary)
            context.draw(text, at: CGPoint(x: tick.x + 3, y: topInset), anchor: .topLeading)
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
    /// item has at least one placed line — ribbons are a read-only reference
    /// layer outside Lyric mode (ADR-026). Lives in the zoomable scroll content,
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
