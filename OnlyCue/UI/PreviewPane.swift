import AVFoundation
import SwiftUI

struct PreviewPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    var selectedCueIDs: Set<Cue.ID> = []
    var onSelectCue: (Cue.ID) -> Void = { _ in }
    var onToggleCue: (Cue.ID) -> Void = { _ in }

    @Environment(\.undoManager) private var undoManager
    @State private var waveformURL: URL?
    @AppStorage("showNotesOverlay") private var showNotesOverlay = false
    @AppStorage("showTimelineBreakdown") private var showTimelineBreakdown = false
    @AppStorage(NotesOverlayPreferences.storageKey) private var overlayPrefsData = NotesOverlayPreferences.defaultEncoded

    var body: some View {
        ZStack {
            Color.black.opacity(0.05)
            content
        }
        .frame(minHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("previewPane")
        .task(id: document.model.activeItemID) { await resolveWaveformURL() }
        .overlay(alignment: overlayAlignment) {
            if showNotesOverlay {
                NotesOverlayView(
                    activeCue: activeCue,
                    prefs: overlayPrefs,
                    cueNumberLabel: activeCue.map { FadeTime.formatNumber($0.cueNumber) }
                )
                .padding(overlayPadding, 12)
            }
        }
    }

    private var activeCue: Cue? {
        document.model.activeItem?.activeCue(at: engine.currentTime)
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
        VStack(spacing: 0) {
            videoPlayer
            timeline(item: item)
                .frame(height: showTimelineBreakdown ? 160 : 100)
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
        WaveformContainer(
            asset: AVURLAsset(url: url),
            cues: item.cues,
            tempoMap: item.tempoMap,
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
            engine: withPlayhead ? engine : nil
        )
        .id(url)
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
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
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Import audio or video to preview")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
