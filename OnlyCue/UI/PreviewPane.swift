import AVFoundation
import SwiftUI

struct PreviewPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    var selectedCueID: Cue.ID?

    @Environment(\.undoManager) private var undoManager
    @State private var waveformURL: URL?
    @AppStorage("showNotesOverlay") private var showNotesOverlay = false
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
            placeholder("Import audio or video to preview")
                .accessibilityIdentifier("emptyPreview")
        }
    }

    @ViewBuilder
    private func videoContent(item: MediaItem) -> some View {
        VStack(spacing: 0) {
            videoPlayer
            if let url = waveformURL {
                waveform(for: url, item: item, withPlayhead: true)
                    .frame(height: 100)
                    .accessibilityIdentifier("videoWaveform")
            }
        }
    }

    private var videoPlayer: some View {
        AVPlayerLayerView(player: engine.player)
            .accessibilityIdentifier("videoPreview")
    }

    @ViewBuilder
    private func audioContent(item: MediaItem) -> some View {
        if let url = waveformURL {
            waveform(for: url, item: item, withPlayhead: true)
                .accessibilityIdentifier("audioWaveform")
        } else {
            placeholder("Loading…")
                .accessibilityIdentifier("audioPlaceholder")
        }
    }

    private func waveform(for url: URL, item: MediaItem, withPlayhead: Bool = false) -> some View {
        WaveformContainer(
            asset: AVURLAsset(url: url),
            cues: item.cues,
            resolveColorHex: { document.model.colorHex(for: $0) },
            selectedCueID: selectedCueID,
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
