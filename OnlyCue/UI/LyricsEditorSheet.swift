import AppKit
import SwiftUI

/// Self-contained editor for one `MediaItem`'s lyrics, reached via
/// `Tools → Lyrics Editor…`. Holds a working draft of the lyric lines; commits
/// flow through `CueCommands` so undo and document-edit tracking work. Tap-along
/// and the offset control extend this view in later leaves.
struct LyricsEditorSheet: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var lines: [LyricLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lyrics Editor")
                .font(.headline)
            Divider()

            if document.model.activeItem == nil {
                Text("Import a media item to add lyrics.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
                controls
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 460)
        .accessibilityIdentifier("lyricsEditorSheet")
        .onAppear { lines = document.model.activeItem?.lyrics.lines ?? [] }
    }

    private var table: some View {
        List {
            ForEach($lines) { $line in
                LyricsEditorRow(line: $line, onCommit: commit, onDelete: { delete(line.id) })
            }
        }
        .accessibilityIdentifier("lyricsEditorTable")
    }

    private var controls: some View {
        HStack {
            Button("Add Line", action: addLine)
                .accessibilityIdentifier("lyricsEditorAddLine")
            Button("Paste Lyrics", action: pasteFromClipboard)
                .accessibilityIdentifier("lyricsEditorPaste")
            Spacer()
        }
    }

    // MARK: - Mutations

    private func addLine() {
        lines.append(LyricLine(time: 0, text: ""))
        commit()
    }

    private func delete(_ id: LyricLine.ID) {
        lines.removeAll { $0.id == id }
        commit()
    }

    private func pasteFromClipboard() {
        guard let itemID = document.model.activeItemID,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        CueCommands.pasteLyrics(plainText: text, itemID: itemID, document: document, undoManager: undoManager)
        lines = document.model.activeItem?.lyrics.lines ?? []
    }

    /// Commits the working draft. `setLyricLines` is a no-op when unchanged, so
    /// redundant commits are cheap.
    private func commit() {
        guard let itemID = document.model.activeItemID else { return }
        CueCommands.setLyricLines(lines, itemID: itemID, document: document, undoManager: undoManager)
        // Re-read so the draft reflects `Lyrics`' normalization (sort).
        lines = document.model.activeItem?.lyrics.lines ?? []
    }
}

/// One editable `[time | text]` row.
private struct LyricsEditorRow: View {

    @Binding var line: LyricLine
    let onCommit: () -> Void
    let onDelete: () -> Void

    @State private var timeText: String = ""
    @FocusState private var timeFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("0:00.000", text: $timeText)
                .frame(width: 96)
                .focused($timeFieldFocused)
                .onAppear { timeText = LyricsTimeFormat.string(line.time) }
                .onSubmit(commitTime)
                .onChange(of: timeFieldFocused) { _, focused in if !focused { commitTime() } }
                .accessibilityIdentifier("lyricsEditorRowTime")

            TextField("lyric line", text: $line.text)
                .onSubmit(onCommit)
                .accessibilityIdentifier("lyricsEditorRowText")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("lyricsEditorRowDelete")
        }
        .accessibilityIdentifier("lyricsEditorRow-\(line.id.uuidString)")
    }

    /// Parses the time field; reverts to the canonical string on bad input.
    private func commitTime() {
        if let parsed = LyricsTimeFormat.parse(timeText) {
            line.time = parsed
            onCommit()
        }
        timeText = LyricsTimeFormat.string(line.time)
    }
}

// MARK: - Host modifier

/// Presents the Lyrics Editor when `Tools → Lyrics Editor…` posts
/// `.lyricsEditorRequested`. Mirrors the `TimecodeSettingsSheetHost` pattern so
/// `DocumentView`'s body stays under the SwiftLint type-body cap.
private struct LyricsEditorSheetHost: ViewModifier {
    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .lyricsEditorRequested)) { _ in
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                LyricsEditorSheet(document: document, engine: engine)
            }
    }
}

extension View {
    func lyricsEditorSheet(engine: PlayerEngine, document: CueListDocument) -> some View {
        modifier(LyricsEditorSheetHost(document: document, engine: engine))
    }
}
