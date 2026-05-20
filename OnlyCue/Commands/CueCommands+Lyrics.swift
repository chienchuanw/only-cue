import Foundation

/// Lyrics commands (schema v13). Lyrics are a per-`MediaItem` annotation layer
/// decoupled from cues (ADR-022). Every mutation routes through here so undo and
/// document-edit tracking work, mirroring the other `CueCommands` extensions.
@MainActor
extension CueCommands {

    /// Primitive: replace an item's whole `Lyrics` value. One undo step; no-op
    /// when the value is unchanged.
    static func setLyrics(
        _ lyrics: Lyrics,
        itemID: MediaItem.ID,
        actionName: String = "Edit Lyrics",
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let before = document.model.items[index].lyrics
        guard before != lyrics else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        document.model.items[index].lyrics = lyrics
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setLyrics(before, itemID: itemID, actionName: actionName, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    /// Sets the lyrics offset — the media time at which the song begins.
    static func setLyricsOffset(
        _ offsetSeconds: TimeInterval,
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let updated = document.model.items[index].lyrics.settingOffset(offsetSeconds)
        setLyrics(updated, itemID: itemID, actionName: "Change Lyrics Offset", document: document, undoManager: undoManager)
    }

    /// Replaces an item's lyric lines (table edits and tap-along stamps).
    static func setLyricLines(
        _ lines: [LyricLine],
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let updated = document.model.items[index].lyrics.settingLines(lines)
        setLyrics(updated, itemID: itemID, actionName: "Edit Lyrics", document: document, undoManager: undoManager)
    }

    /// Replaces an item's lyric lines with untimed rows parsed from pasted plain
    /// text. Preserves the existing offset.
    static func pasteLyrics(
        plainText: String,
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let updated = document.model.items[index].lyrics
            .settingLines(Lyrics.untimedLines(fromPlainText: plainText))
        setLyrics(updated, itemID: itemID, actionName: "Paste Lyrics", document: document, undoManager: undoManager)
    }

    /// Places (or retimes) one lyric line at a media playback time. Stores a
    /// SONG-relative time — `mediaTime − offset`, clamped `>= 0` — so the line's
    /// effective time lands exactly at `mediaTime`. Used by click-to-drop,
    /// tap-along, and drag-to-retime.
    static func placeLyricLine(
        id: LyricLine.ID,
        atMediaTime mediaTime: TimeInterval,
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let lyrics = document.model.items[index].lyrics
        guard let lineIndex = lyrics.lines.firstIndex(where: { $0.id == id }) else { return }
        var lines = lyrics.lines
        lines[lineIndex].time = max(0, mediaTime - lyrics.offsetSeconds)
        setLyrics(
            lyrics.settingLines(lines),
            itemID: itemID,
            actionName: "Place Lyric Line",
            document: document,
            undoManager: undoManager
        )
    }

    /// Returns a placed line to the unplaced queue (clears its `time`).
    static func unplaceLyricLine(
        id: LyricLine.ID,
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let lyrics = document.model.items[index].lyrics
        guard let lineIndex = lyrics.lines.firstIndex(where: { $0.id == id }) else { return }
        var lines = lyrics.lines
        lines[lineIndex].time = nil
        setLyrics(
            lyrics.settingLines(lines),
            itemID: itemID,
            actionName: "Unplace Lyric Line",
            document: document,
            undoManager: undoManager
        )
    }

    /// Removes a lyric line entirely.
    static func deleteLyricLine(
        id: LyricLine.ID,
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let lyrics = document.model.items[index].lyrics
        guard lyrics.lines.contains(where: { $0.id == id }) else { return }
        setLyrics(
            lyrics.settingLines(lyrics.lines.filter { $0.id != id }),
            itemID: itemID,
            actionName: "Delete Lyric Line",
            document: document,
            undoManager: undoManager
        )
    }
}
