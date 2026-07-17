import AVFoundation
import SwiftUI

/// Identity for the waveform-resolve task. Keyed on the active item id AND its
/// bookmark so a relink — which mutates `media.bookmarkData` in place on the
/// same item id — still re-fires the resolve and refreshes the waveform,
/// instead of leaving it stuck on the spinner until the user toggles media
/// (#589).
struct WaveformSourceKey: Equatable {
    let itemID: MediaItem.ID?
    let bookmark: Data?
}

struct PreviewPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    var selectedCueIDs: Set<Cue.ID> = []
    var onSelectCue: (Cue.ID) -> Void = { _ in }
    var onToggleCue: (Cue.ID) -> Void = { _ in }
    var editorMode: EditorMode = .cue
    var setEditorMode: (EditorMode) -> Void = { _ in }
    @Binding var lyricsCursor: LyricsAuthoringCursor
    /// Show-mode GO-by-type filter (#657): nil = All cues. When non-nil the
    /// notes overlay's "current cue" is the latest cue of that type at/before
    /// the playhead, matching what GO walks.
    var activeCueTypeID: CuePointType.ID?

    @Environment(\.undoManager) private var undoManager
    @State private var waveformURL: URL?
    @AppStorage("showNotesOverlay") private var showNotesOverlay = false
    @AppStorage("showLyricsOverlay") private var showLyricsOverlay = false
    @AppStorage("showTimelineBreakdown") private var showTimelineBreakdown = false
    @AppStorage(NotesOverlayPreferences.storageKey) private var overlayPrefsData = NotesOverlayPreferences.defaultEncoded

    /// Re-resolves the waveform whenever the active item or its bookmark changes
    /// (the latter covers relink — same id, new bookmark) (#589).
    private var waveformSourceKey: WaveformSourceKey {
        WaveformSourceKey(
            itemID: document.model.activeItemID,
            bookmark: document.model.activeItem?.media.bookmarkData
        )
    }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            // Left-aligned switcher bar (Figma 318:1250 — EditorModeSwitcher at
            // x=16), not centered.
            HStack(spacing: 0) {
                EditorModeSwitcher(mode: editorMode, setMode: setEditorMode)
                Spacer(minLength: 0)
            }
            .padding(.leading, PreviewLayout.switcherLeadingInset)
            ZStack {
                DS.Color.surfaceSunken
                content
            }
            // Fill the center pane (Figma 318:1252 — the preview/waveform well
            // is the dominant vertical block, ~80% of the center height), so the
            // transport bar sits as a thin row beneath it rather than floating in
            // a large empty box.
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .accessibilityIdentifier("previewPane")
            .task(id: waveformSourceKey) { await resolveWaveformURL() }
            // Bottom stack — the Notes Overlay (when its position is bottom)
            // above the Lyrics HUD. The spec stacks notes above lyrics;
            // non-bottom Notes Overlay positions keep their own overlay below.
            .overlay(alignment: .bottom) {
                VStack(spacing: DS.Space.sm) {
                    if showNotesOverlay, overlayPrefs.position == .bottom {
                        notesOverlayCard
                    }
                    if showLyricsOverlay, let item = document.model.activeItem {
                        LyricsOverlayView(lyrics: item.lyrics, mediaSeconds: engine.currentTime)
                    }
                }
                .padding(.bottom, DS.Space.md)
            }
            .overlay(alignment: overlayAlignment) {
                if showNotesOverlay, overlayPrefs.position != .bottom {
                    notesOverlayCard
                        .padding(overlayPadding, DS.Space.md)
                }
            }
            // The waveform well is inset 16pt inside the full-width preview area
            // (Figma 318:1252/318:1253); the pane itself is edge-to-edge now that
            // mainPane drops its outer padding.
            .padding(.horizontal, DS.Space.lg)
        }
        // Top breathing for the switcher bar (Figma 318:1250 centers it in a
        // 62pt bar) — needed now that mainPane has no outer padding.
        .padding(.top, DS.Space.md)
    }

    private var activeCue: Cue? {
        document.model.activeItem?.activeCue(at: engine.currentTime, typeID: activeCueTypeID)
    }

    private var notesOverlayCard: some View {
        NotesOverlayView(
            activeCue: activeCue,
            prefs: overlayPrefs,
            cueNumberLabel: activeCue.flatMap { $0.cueNumber.map(FadeTime.formatNumber) }
        )
    }

    private var overlayPrefs: NotesOverlayPreferences {
        NotesOverlayPreferences.decode(overlayPrefsData)
    }

    private var overlayAlignment: Alignment {
        switch overlayPrefs.position {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }

    private var overlayPadding: Edge.Set {
        switch overlayPrefs.position {
        case .top: .top
        case .center: []
        case .bottom: .bottom
        }
    }

    @ViewBuilder
    private var content: some View {
        if let item = document.model.activeItem {
            switch item.media.kind {
            case .video:
                videoContent(item: item)
            case .audio:
                audioContent(item: item)
            }
        } else {
            emptyPreviewPlaceholder
                .accessibilityIdentifier("emptyPreview")
        }
    }

    @ViewBuilder
    private func videoContent(item: MediaItem) -> some View {
        // Proportional split (Figma 318:1639): the video letterbox fills the top
        // and the waveform/timeline takes a ~26% band beneath it, rather than a
        // fixed 100pt that leaves the well mostly empty as the window grows.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                videoPlayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                timeline(item: item)
                    .frame(height: PreviewLayout.videoTimelineHeight(
                        totalHeight: proxy.size.height,
                        breakdown: showTimelineBreakdown
                    ))
            }
        }
    }

    private var videoPlayer: some View {
        AVPlayerLayerView(player: engine.player)
            .accessibilityIdentifier("videoPreview")
    }

    @ViewBuilder
    private func audioContent(item: MediaItem) -> some View {
        timeline(item: item)
    }

    /// The timeline area below/inside the preview: the per-Type breakdown lanes
    /// when `View → Show Timeline Breakdown` is on, otherwise the waveform view.
    /// The breakdown view needs no decoded audio (it positions markers off
    /// `media.duration`, which is in the model) — so it renders even while the
    /// waveform URL is still resolving or the media file is missing.
    @ViewBuilder
    private func timeline(item: MediaItem) -> some View {
        if showTimelineBreakdown {
            TimelineBreakdownView(
                cues: item.cues,
                types: document.model.cuePointTypes,
                duration: item.media.duration,
                selectedCueIDs: selectedCueIDs,
                onSelectCue: onSelectCue,
                onSeek: { time in Task { await engine.seek(to: time) } },
                onHideType: { typeId in
                    CueCommands.setCuePointTypeVisibility(id: typeId, to: false, document: document, undoManager: undoManager)
                },
                onShowType: { typeId in
                    CueCommands.setCuePointTypeVisibility(id: typeId, to: true, document: document, undoManager: undoManager)
                },
                onShowAllTypes: {
                    CueCommands.showAllCuePointTypes(document: document, undoManager: undoManager)
                },
                engine: engine
            )
            .accessibilityIdentifier("timelineBreakdownArea")
        } else if let url = waveformURL {
            waveform(for: url, item: item, withPlayhead: true)
                .accessibilityIdentifier(item.media.kind == .video ? "videoWaveform" : "audioWaveform")
        } else {
            placeholder("Loading…")
                .accessibilityIdentifier(item.media.kind == .video ? "videoPlaceholder" : "audioPlaceholder")
        }
    }

    private func waveform(for url: URL, item: MediaItem, withPlayhead: Bool = false) -> some View {
        waveformContainer(for: url, item: item, withPlayhead: withPlayhead)
            .id(url)
    }

    private func waveformContainer(for url: URL, item: MediaItem, withPlayhead: Bool) -> some View {
        WaveformContainer(
            asset: AVURLAsset(url: url),
            cues: item.cues,
            tempoGrid: DerivedTempoGrid.from(cues: item.cues),
            resolveColorHex: { document.model.colorHex(for: $0) },
            selectedCueIDs: selectedCueIDs,
            onSelectCue: onSelectCue,
            onToggleCue: onToggleCue,
            onSeek: { time in Task { await engine.seek(to: time) } },
            onRetime: { cueId, newTime in
                CueCommands.retime(
                    cueId: cueId,
                    to: newTime,
                    document: document,
                    undoManager: undoManager
                )
            },
            onNudge: { ids, delta in
                CueCommands.nudgeCues(ids, by: delta, document: document, undoManager: undoManager)
            },
            engine: withPlayhead ? engine : nil,
            lyrics: item.lyrics,
            onSeekToLyric: { time in Task { await engine.seek(to: time) } },
            editorMode: editorMode,
            onRetimeLyric: { id, newTime in
                CueCommands.placeLyricLine(
                    id: id,
                    atMediaTime: newTime,
                    itemID: item.id,
                    document: document,
                    undoManager: undoManager
                )
            },
            onUnplaceLyric: { id in
                CueCommands.unplaceLyricLine(id: id, itemID: item.id, document: document, undoManager: undoManager)
            },
            onDeleteLyric: { id in
                CueCommands.deleteLyricLine(id: id, itemID: item.id, document: document, undoManager: undoManager)
            },
            ghostLyricLine: ghostLyricLine(for: item),
            onPlaceLyricAtMediaTime: { placeGhostLyric(atMediaTime: $0, item: item) }
        )
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(DS.Text.body)
            .foregroundStyle(DS.Color.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
    }

    /// Clickable empty-preview placeholder — same notification path as the
    /// Import Media button + ⌘O so all three entry points converge on the
    /// same file picker. Wrapped in a `.plain` button style so the hit area
    /// fills the preview frame without macOS's default chrome competing with
    /// the icon-led layout.
    private var emptyPreviewPlaceholder: some View {
        Button {
            NotificationCenter.default.post(name: .importMediaRequested, object: nil)
        } label: {
            VStack(spacing: DS.Space.sm) {
                Image(systemName: "square.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundStyle(DS.Color.textTertiary)
                Text("Import audio or video to preview")
                    .font(DS.Text.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Import Media (⌘O)")
    }

    private func resolveWaveformURL() async {
        waveformURL = nil
        guard let bookmarkData = document.model.activeItem?.media.bookmarkData else { return }
        let resolved = await Task.detached(priority: .userInitiated) {
            try? Bookmarks.resolve(bookmarkData)
        }.value
        if document.model.activeItem?.media.bookmarkData == bookmarkData {
            waveformURL = resolved?.url
        }
    }
}

/// Lyric-placement helpers. Split into an extension so the main `PreviewPane`
/// body stays under the SwiftLint `type_body_length` cap.
extension PreviewPane {

    /// Places the resolved cursor line at `mediaTime` and advances the cursor
    /// (click-to-drop). No-op when the queue is empty.
    fileprivate func placeGhostLyric(atMediaTime mediaTime: TimeInterval, item: MediaItem) {
        guard let targetID = ghostLyricLineID(for: item) else { return }
        CueCommands.placeLyricLine(
            id: targetID,
            atMediaTime: mediaTime,
            itemID: item.id,
            document: document,
            undoManager: undoManager
        )
        let remaining = document.model.activeItem?.lyrics.unplacedLines ?? []
        lyricsCursor.advance(afterPlacing: targetID, remainingUnplaced: remaining)
    }

    /// The id of the unplaced line the next placement gesture targets.
    fileprivate func ghostLyricLineID(for item: MediaItem) -> LyricLine.ID? {
        lyricsCursor.resolvedCursorID(unplaced: item.lyrics.unplacedLines)
    }

    /// The ghost line shown riding the cursor on the lane — only in Lyric mode.
    fileprivate func ghostLyricLine(for item: MediaItem) -> LyricLine? {
        guard editorMode.lyricsEditable, let id = ghostLyricLineID(for: item) else { return nil }
        return item.lyrics.unplacedLines.first { $0.id == id }
    }
}
