import AVFoundation
import QuartzCore
import SwiftUI

/// Load key for `WaveformContainer`'s generation task. Captures both the asset
/// URL and the detected LTC channel index so the task re-fires when async LTC
/// detection resolves after the clip loads. Without the channel in the key the
/// waveform renders all-channel on first load and never refreshes to music-only
/// when detection arrives (#715).
struct WaveformLoadKey: Hashable {
    let url: URL
    let excludingChannel: Int?
}

struct WaveformContainer: View {

    let asset: AVURLAsset
    /// The horizontal-zoom controller. Injected (not `@State`-owned) so the LTC
    /// strip can share the same instance and stay zoom/scroll-synced (#669).
    var zoom: WaveformZoomController
    var resolution: Int = 12_000
    var cues: [Cue] = []
    var tempoGrid: DerivedTempoGrid = DerivedTempoGrid(segments: [])
    var resolveColorHex: (Cue) -> String? = { _ in nil }
    var selectedCueIDs: Set<Cue.ID> = []
    var onSelectCue: (Cue.ID) -> Void = { _ in }
    var onToggleCue: (Cue.ID) -> Void = { _ in }
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }
    var onNudge: (Set<Cue.ID>, TimeInterval) -> Void = { _, _ in }
    var engine: PlayerEngine?
    var lyrics: Lyrics = .empty
    var onSeekToLyric: (TimeInterval) -> Void = { _ in }
    var editorMode: EditorMode = .cue
    var onRetimeLyric: (LyricLine.ID, TimeInterval) -> Void = { _, _ in }
    var onUnplaceLyric: (LyricLine.ID) -> Void = { _ in }
    var onDeleteLyric: (LyricLine.ID) -> Void = { _ in }
    var ghostLyricLine: LyricLine?
    var onPlaceLyricAtMediaTime: (TimeInterval) -> Void = { _ in }

    @State private var peaks: [Float]?
    @State private var failed = false
    @State var loadedDuration: TimeInterval = 0
    @State var scrub = ScrubController()
    @State private var seekTask: Task<Void, Never>?
    @AppStorage("showTempoGrid") var showTempoGrid = false
    // Persisted "Auto-Scroll Waveform" preference (#532), default on. Drives the
    // zoom controller's auto-follow gate; synced on appear and on change so a
    // media load (which resets zoom/offset) can't silently flip it back on.
    @AppStorage("autoScrollWaveform") var autoScrollWaveform = true

    @State var pinchBaseline: CGFloat = 1
    @State var isHoveringWaveform = false
    @State var hintShowing = false
    /// Device pixel scale — the follow offset is snapped to this grid so the
    /// waveform envelope translates without sub-pixel resampling (shimmer, #677).
    @Environment(\.displayScale) var displayScale
    /// The LTC track detected on the active clip — nil when no LTC is present.
    /// Used to exclude the timecode channel from the rendered waveform peaks so
    /// the display shows music only (#715). The nil path is byte-identical to
    /// the pre-#715 all-channel downmix (Task 3 guarantee).
    @Environment(\.stripedTimecode) private var stripedTimecode

    var body: some View {
        Group {
            if let peaks {
                loaded(peaks: peaks)
            } else if failed {
                Text("Could not generate waveform")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("waveformLoading")
            }
        }
        .task(id: WaveformLoadKey(url: asset.url, excludingChannel: stripedTimecode?.ltcChannel)) {
            await load()
        }
        .onAppear { zoom.followsPlayhead = autoScrollWaveform }
        .onChange(of: autoScrollWaveform) { _, enabled in zoom.followsPlayhead = enabled }
        // When playback stops, persist the last follow offset into the stored
        // scroll offset once (#677) so play→pause is seamless and later manual
        // scrolling starts from where the waveform actually is.
        .onChange(of: engine?.isPlaying ?? false) { _, playing in
            if !playing { persistFollowOffsetOnPause() }
        }
        .onChange(of: selectedCueIDs) { _, _ in scrollToSelectedCue() }
        .onReceive(NotificationCenter.default.publisher(for: .waveformZoomIn)) { _ in applyZoomIn() }
        .onReceive(NotificationCenter.default.publisher(for: .waveformZoomOut)) { _ in applyZoomOut() }
        .onReceive(NotificationCenter.default.publisher(for: .waveformZoomReset)) { _ in applyZoomReset() }
    }

    @ViewBuilder
    private func loaded(peaks: [Float]) -> some View {
        waveformBody(peaks: peaks)
            // The waveform's inner content inset — shared with the LTC strip via
            // `PreviewLayout` so the two playhead tracks coincide (#663).
            .padding(.horizontal, PreviewLayout.trackContentInset)
            .overlay(alignment: .trailing) {
                magnifier.padding(.trailing, 8)
            }
            .onHover { hovering in
                isHoveringWaveform = hovering
            }
            .task {
                guard !FirstLaunchHintTracker.shared.hasShownWaveformZoomHint else { return }
                FirstLaunchHintTracker.shared.markShown()
                hintShowing = true
                try? await Task.sleep(for: .seconds(1.5))
                hintShowing = false
            }
    }

    @ViewBuilder
    private func waveformBody(peaks: [Float]) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let contentWidth = zoom.contentWidth(viewportWidth: width)

            // Continuous pixel-offset render (#675): draw the content at
            // `contentWidth`, shift by the scroll offset, clip to the viewport —
            // smooth at any zoom, no anchor buckets. Manual scrolling comes from
            // the scroll-wheel reader (the ScrollView it replaced).
            HorizontalScrollWheelReader(
                onScroll: { dx in manualScroll(dx: dx, viewportWidth: width) },
                content: {
                    offsetScrollContent(peaks: peaks, width: width, contentWidth: contentWidth, height: height)
                }
            )
            .gesture(magnifyGesture(viewportWidth: width))
            .onAppear { viewportWidth = width }
            .onChange(of: width) { _, new in
                viewportWidth = new
                clampScrollOffset(viewportWidth: new)
            }
            .onChange(of: zoom.zoom) { _, _ in clampScrollOffset(viewportWidth: width) }
        }
    }

    /// Manual horizontal scroll from the wheel reader — natural-scroll direction,
    /// clamped to the content (#675). No-op at 1× (whole track fits).
    private func manualScroll(dx: CGFloat, viewportWidth: CGFloat) {
        guard zoom.zoom > 1 else { return }
        clampScrollOffset(viewportWidth: viewportWidth, proposed: scrollOffset - dx)
    }

    /// Clamps `scrollOffset` to `[0, contentWidth − viewport]` (optionally to a
    /// proposed value) — after resize, zoom, or manual scroll.
    private func clampScrollOffset(viewportWidth: CGFloat, proposed: CGFloat? = nil) {
        let contentWidth = zoom.contentWidth(viewportWidth: viewportWidth)
        let maxOffset = max(contentWidth - viewportWidth, 0)
        scrollOffset = min(max(proposed ?? scrollOffset, 0), maxOffset)
    }

    /// The STATIC zoomable content — waveform peaks, tempo grid + time ruler,
    /// click-to-seek surface (below markers so marker presses win), cue markers,
    /// lyric lane. Everything except the playhead. During follow it is rendered
    /// ONCE (outside the per-frame `TimelineView`) and only translated each
    /// frame, so the wide waveform Canvas is not re-rasterized 60×/s at high zoom
    /// (#681). The playhead — the only per-frame element — is `playheadLayer`.
    func staticScrollContent(
        peaks: [Float],
        width: CGFloat,
        contentWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // Audit §9.1: Show mode dims the waveform peaks to convey the
            // "show-running" locked state while leaving cue markers and the
            // seek surface at full contrast.
            WaveformView(peaks: peaks)
                .opacity(editorMode == .show ? 0.45 : 1)
            tempoGridOverlay()
            timeRulerOverlay()
            if let engine, loadedDuration > 0 {
                // Seek surface BELOW the markers so a press on a cue marker
                // reaches `CueMarkerView` instead of being absorbed by the
                // full-bleed click-to-seek surface.
                WaveformSeekSurface(
                    engine: engine,
                    duration: loadedDuration,
                    scrub: $scrub,
                    seekTask: $seekTask
                )
            }
            markersOverlay()
            lyricsLaneOverlay()
        }
        .frame(width: contentWidth, height: height, alignment: .leading)
    }

    /// The playhead line + time-label badge, ABOVE the markers so a selected
    /// (wider) cap never occludes them. `overrideTime` non-nil (following) draws
    /// at that shared per-frame sample; nil self-animates (#681).
    @ViewBuilder
    func playheadLayer(overrideTime: TimeInterval?, contentWidth: CGFloat, height: CGFloat) -> some View {
        if let engine, loadedDuration > 0 {
            WaveformPlayheadVisual(
                engine: engine,
                duration: loadedDuration,
                scrub: $scrub,
                overrideTime: overrideTime
            )
            .frame(width: contentWidth, height: height, alignment: .leading)
        }
    }

    private func magnifyGesture(viewportWidth: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = pinchBaseline * CGFloat(value.magnification)
                let anchorFraction = max(min(value.startLocation.x / viewportWidth, 1), 0)
                var temp = scrollOffset
                zoom.setZoom(
                    next,
                    anchorFraction: anchorFraction,
                    viewportWidth: viewportWidth,
                    scrollOffset: &temp
                )
                scrollOffset = temp
            }
            .onEnded { _ in
                pinchBaseline = zoom.zoom
            }
    }

    func applyZoomReset() {
        var offset = scrollOffset
        zoom.reset(scrollOffset: &offset)
        scrollOffset = offset
        pinchBaseline = 1
    }

    private func applyAutoFollow(targetOffset: CGFloat, viewportWidth: CGFloat) {
        scrollOffset = targetOffset
    }

    private func load() async {
        peaks = nil
        failed = false
        var resetOffset = scrollOffset
        zoom.reset(scrollOffset: &resetOffset)
        scrollOffset = resetOffset
        pinchBaseline = 1

        let cache = WaveformCache.shared
        let target = resolution
        let url = asset.url
        // Capture at task-start so the three call sites use a consistent value
        // even if the environment updates mid-load. nil when no LTC is detected.
        let excludingChannel = stripedTimecode?.ltcChannel

        do {
            let hash: String? = await Task.detached(priority: .userInitiated) {
                try? WaveformCache.fileHash(url)
            }.value

            if Task.isCancelled { return }

            let cmDuration = try await asset.load(.duration)
            loadedDuration = CMTimeGetSeconds(cmDuration)

            if let hash, let cached = cache.read(
                assetHash: hash,
                resolution: target,
                excludingChannel: excludingChannel
            ) {
                peaks = cached
                return
            }

            let generated = try await WaveformGenerator.peaks(
                for: asset,
                resolution: target,
                excludingChannel: excludingChannel
            )
            if Task.isCancelled { return }
            peaks = generated

            if let hash {
                Task.detached(priority: .background) {
                    try? cache.write(
                        generated,
                        assetHash: hash,
                        resolution: target,
                        excludingChannel: excludingChannel
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}

extension WaveformContainer {
    // scrollOffset and viewportWidth are stored on the `zoom` controller (an
    // @Observable reference type) so they survive SwiftUI struct copies and are
    // directly mutable in tests without going through the @State wrapper's
    // SwiftUI-only nonmutating-set path. Kept in this extension (not the main
    // struct body) so `WaveformContainer` stays under the `type_body_length` cap.
    var scrollOffset: CGFloat {
        get { zoom.scrollOffset }
        nonmutating set { zoom.scrollOffset = newValue }
    }
    var viewportWidth: CGFloat {
        get { zoom.viewportWidth }
        nonmutating set { zoom.viewportWidth = newValue }
    }

    /// Scrolls the waveform to reveal the sole-selected cue's marker (#536).
    /// No-op when zoomed out, the cue is already visible, or selection isn't a
    /// single cue. Reuses the auto-follow apply path (sets the scroll offset). In
    /// this extension so the main struct body stays under `type_body_length`.
    func scrollToSelectedCue() {
        guard selectedCueIDs.count == 1,
              let id = selectedCueIDs.first,
              let cue = cues.first(where: { $0.id == id }) else { return }
        guard let target = zoom.scrollToRevealAdjustment(
            targetTime: cue.time,
            duration: loadedDuration,
            viewportWidth: viewportWidth,
            currentScrollOffset: scrollOffset
        ) else { return }
        applyAutoFollow(targetOffset: target, viewportWidth: viewportWidth)
    }

    fileprivate func applyZoomIn() {
        mutateZoom { width, offset in
            zoom.zoomIn(viewportWidth: width, scrollOffset: &offset)
        }
    }

    fileprivate func applyZoomOut() {
        mutateZoom { width, offset in
            zoom.zoomOut(viewportWidth: width, scrollOffset: &offset)
        }
    }

    fileprivate func mutateZoom(_ block: (CGFloat, inout CGFloat) -> Void) {
        guard viewportWidth > 0 else { return }
        var offset = scrollOffset
        block(viewportWidth, &offset)
        scrollOffset = offset
        pinchBaseline = zoom.zoom
    }
}

extension Notification.Name {
    static let waveformZoomIn = Notification.Name("OnlyCue.waveformZoomIn")
    static let waveformZoomOut = Notification.Name("OnlyCue.waveformZoomOut")
    static let waveformZoomReset = Notification.Name("OnlyCue.waveformZoomReset")
}
