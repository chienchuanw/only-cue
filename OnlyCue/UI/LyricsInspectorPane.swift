import AppKit
import SwiftUI

/// The Lyric-mode inspector: a paste box, the unplaced-line queue (cursor
/// highlighted), the placed lines with editable text, and the offset control.
/// All mutation routes through `CueCommands`.
struct LyricsInspectorPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @Binding var lyricsCursor: LyricsAuthoringCursor
    @Environment(\.undoManager) private var undoManager

    private var item: MediaItem? { document.model.activeItem }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let item {
                offsetControl(item: item)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        queueSection(item: item)
                        Divider()
                        placedSection(item: item)
                    }
                }
                pasteButton(item: item)
            } else {
                Text("Import a media item to add lyrics.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("lyricsInspectorPane")
    }

    /// The uppercase `LYRICS` caption + a pluralised total-line count badge,
    /// right-aligned — mirrors `CueListSectionHeader` (Figma `318:1469`, #413).
    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Text("Lyrics")
                .dsSectionHeader()
                .accessibilityIdentifier("lyricsInspectorCaption")
            Spacer(minLength: DS.Space.xs)
            if let item {
                Text(Self.lineCountText(for: item.lyrics.lines.count))
                    .font(DS.Text.label)
                    .foregroundStyle(DS.Color.textSecondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("lyricsInspectorLineCount")
            }
        }
    }

    /// Pure pluralisation helper — extracted so the contract is unit-testable
    /// without standing up a SwiftUI hosting view (mirrors
    /// `CueListSectionHeader.countText(for:)`).
    static func lineCountText(for count: Int) -> String {
        count == 1 ? "1 line" : "\(count) lines"
    }

    private func offsetControl(item: MediaItem) -> some View {
        LyricsOffsetControl(
            offsetSeconds: item.lyrics.offsetSeconds,
            playhead: { engine.currentTime },
            onCommit: { newOffset in
                CueCommands.setLyricsOffset(
                    newOffset,
                    itemID: item.id,
                    document: document,
                    undoManager: undoManager
                )
            }
        )
        .font(.caption)
    }

    @ViewBuilder
    private func queueSection(item: MediaItem) -> some View {
        let unplaced = item.lyrics.unplacedLines
        Text("Unplaced · Next to place")
            .dsSectionHeader()
            .accessibilityIdentifier("lyricsUnplacedSectionCaption")
        if unplaced.isEmpty {
            Text("All lines are placed.").font(.caption).foregroundStyle(.secondary)
        } else {
            let cursorID = lyricsCursor.resolvedCursorID(unplaced: unplaced)
            ForEach(unplaced) { line in
                Text(line.text.isEmpty ? "\u{266A}" : line.text)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(line.id == cursorID ? Color.purple.opacity(0.3) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { lyricsCursor.select(line.id) }
                    .accessibilityIdentifier("lyricsQueueRow-\(line.id.uuidString)")
            }
        }
    }

    @ViewBuilder
    private func placedSection(item: MediaItem) -> some View {
        let placed = item.lyrics.placedLines
        let currentID = item.lyrics.activeLine(atMediaSeconds: engine.currentTime)?.id
        Text("Placed")
            .dsSectionHeader()
            .accessibilityIdentifier("lyricsPlacedSectionCaption")
        ForEach(placed) { line in
            LyricsInspectorRow(
                line: line,
                isCurrent: line.id == currentID,
                onCommitText: { newText in commitText(line.id, newText, item: item) }
            )
        }
    }

    /// Replaces one line's text, routing through the command seam. Called when a
    /// placed row's text field commits (submit or focus loss).
    private func commitText(_ id: LyricLine.ID, _ newText: String, item: MediaItem) {
        guard let index = item.lyrics.lines.firstIndex(where: { $0.id == id }) else { return }
        var lines = item.lyrics.lines
        lines[index].text = newText
        CueCommands.setLyricLines(lines, itemID: item.id, document: document, undoManager: undoManager)
    }

    private func pasteButton(item: MediaItem) -> some View {
        Button("Paste Lyrics from Clipboard") {
            guard let text = NSPasteboard.general.string(forType: .string) else { return }
            CueCommands.pasteLyrics(
                plainText: text,
                itemID: item.id,
                document: document,
                undoManager: undoManager
            )
            lyricsCursor.select(nil)
        }
        .accessibilityIdentifier("lyricsInspectorPaste")
    }
}

/// One placed-line row: a read-only timestamp plus an editable text field that
/// commits on submit / focus loss (spec §6 — placed lines have editable text).
private struct LyricsInspectorRow: View {
    let line: LyricLine
    /// True when this is the line whose interval contains the current playhead.
    /// Drives the audit §8.1 "Now playing" emphasis: brand-tinted background,
    /// indigo cue-mark color, and a heavier body font weight.
    var isCurrent: Bool = false
    let onCommitText: (String) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(LyricsTimeFormat.string(line.time ?? 0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? DS.Color.cueIndigo : DS.Color.textSecondary)
            TextField("lyric line", text: $text)
                .focused($focused)
                .font(isCurrent ? DS.Text.body.weight(.semibold) : DS.Text.body)
                .foregroundStyle(isCurrent ? DS.Color.textPrimary : DS.Color.textPrimary)
                .onSubmit { onCommitText(text) }
                .onChange(of: focused) { _, isFocused in if !isFocused { onCommitText(text) } }
        }
        .padding(.horizontal, isCurrent ? 6 : 0)
        .padding(.vertical, isCurrent ? 3 : 0)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? DS.Color.cueIndigo.opacity(0.12) : Color.clear)
        )
        .animation(.easeOut(duration: 0.15), value: isCurrent)
        .onAppear { text = line.text }
        .onChange(of: line.text) { _, newText in
            // Resync when the model changes underneath us (undo/redo) while the
            // field is not being edited — mirrors LyricsOffsetControl.
            if !focused { text = newText }
        }
        .accessibilityIdentifier("lyricsPlacedRow-\(line.id.uuidString)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
