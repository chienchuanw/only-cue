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
}
