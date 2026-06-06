import SwiftUI

/// The lyric lane — a band inside `WaveformContainer`'s zoomable content showing
/// each placed line positioned by its effective time. In Lyric mode it grows
/// into a tall editing strip: chips show full text, drag to retime, right-click
/// to unplace or delete, and a ghost chip rides the cursor for click-to-drop
/// placement. In Cue / Show modes it is the compact, read-only, click-to-seek
/// strip that collapses to ticks when lines pack tightly.
struct LyricsLaneView: View {

    let lyrics: Lyrics
    let duration: TimeInterval
    let editorMode: EditorMode
    let onSeek: (TimeInterval) -> Void
    var onRetime: (LyricLine.ID, TimeInterval) -> Void = { _, _ in }
    var onUnplace: (LyricLine.ID) -> Void = { _ in }
    var onDelete: (LyricLine.ID) -> Void = { _ in }
    /// The unplaced line the next placement gesture will target (the cursor).
    var ghostLine: LyricLine?
    /// Place `ghostLine` at a media time (click-to-drop). Lyric mode only.
    var onPlaceAtMediaTime: (TimeInterval) -> Void = { _ in }

    static let compactHeight: CGFloat = 26
    static let tallHeight: CGFloat = 64

    @State private var dragLineID: LyricLine.ID?
    @State private var dragDX: CGFloat = 0
    @State private var hoverX: CGFloat?

    private var isEditing: Bool { editorMode.lyricsEditable }
    private var laneHeight: CGFloat { isEditing ? Self.tallHeight : Self.compactHeight }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let collapse = !isEditing && LyricsLaneLayout.shouldCollapseToTicks(
                lineCount: lyrics.placedLines.count,
                contentWidth: width
            )
            ZStack(alignment: .bottomLeading) {
                ForEach(lyrics.placedLines) { line in
                    marker(for: line, width: width, collapsed: collapse)
                }
                if isEditing, let ghost = ghostLine {
                    ghostChip(for: ghost)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard isEditing else { hoverX = nil; return }
                switch phase {
                case .active(let point): hoverX = point.x
                case .ended: hoverX = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { location in
                guard isEditing, ghostLine != nil else { return }
                onPlaceAtMediaTime(
                    LyricsLaneInteraction.mediaTime(forX: location.x, width: width, duration: duration)
                )
            }
        }
        .frame(height: laneHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyricsLane")
    }

    @ViewBuilder
    private func marker(for line: LyricLine, width: CGFloat, collapsed: Bool) -> some View {
        let effective = lyrics.effectiveTime(of: line) ?? 0
        let baseX = CueMarkersGeometry.position(forTime: effective, width: width, duration: duration)
        let dx = dragLineID == line.id ? dragDX : 0
        // Cap each compact chip to its slot so a long line can't overrun the
        // next chip (Figma 318:1263). Editing chips show full text.
        let maxWidth = isEditing ? nil : LyricsLaneLayout.chipMaxWidth(
            forTime: effective,
            allTimes: lyrics.placedLines.compactMap { lyrics.effectiveTime(of: $0) },
            duration: duration,
            contentWidth: width
        )
        chip(for: line, collapsed: collapsed, maxWidth: maxWidth)
            .offset(x: baseX + dx)
            .gesture(dragGesture(line: line, effective: effective, width: width))
            .onTapGesture { onSeek(effective) }
            .contextMenu { contextMenu(for: line) }
            .accessibilityIdentifier("lyricsLaneMarker-\(line.id.uuidString)")
    }

    @ViewBuilder
    private func chip(for line: LyricLine, collapsed: Bool, maxWidth: CGFloat?) -> some View {
        if collapsed {
            Rectangle().fill(DS.Color.cueIndigo.opacity(0.7)).frame(width: 1.5, height: 12)
        } else {
            Text(line.text.isEmpty ? "\u{266A}" : line.text)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, isEditing ? 5 : 2)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.Color.cueIndigo.opacity(isEditing ? 0.85 : 0.18)))
                .foregroundStyle(isEditing ? Color.white : Color.primary)
        }
    }

    /// The dashed chip that rides the cursor over the lane, previewing where the
    /// next unplaced line will drop.
    private func ghostChip(for line: LyricLine) -> some View {
        Text(line.text.isEmpty ? "\u{266A}" : line.text)
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DS.Color.cueIndigo, style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.Color.cueIndigo.opacity(0.25)))
            )
            .foregroundStyle(.white)
            .offset(x: hoverX ?? 0)
            .opacity(hoverX == nil ? 0 : 0.9)
            .allowsHitTesting(false)
            .accessibilityIdentifier("lyricsLaneGhostChip")
    }

    @ViewBuilder
    private func contextMenu(for line: LyricLine) -> some View {
        if isEditing {
            Button("Send Back to Unplaced") { onUnplace(line.id) }
            Button("Delete Line", role: .destructive) { onDelete(line.id) }
        }
    }

    private func dragGesture(line: LyricLine, effective: TimeInterval, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isEditing else { return }
                dragLineID = line.id
                dragDX = value.translation.width
            }
            .onEnded { value in
                guard isEditing else { return }
                let newTime = LyricsLaneInteraction.draggedMediaTime(
                    fromMediaTime: effective,
                    dx: value.translation.width,
                    width: width,
                    duration: duration
                )
                dragLineID = nil
                dragDX = 0
                onRetime(line.id, newTime)
            }
    }
}
