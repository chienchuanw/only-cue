import AVFoundation
import SwiftUI

struct WaveformContainer: View {

    let asset: AVURLAsset
    var resolution: Int = 512
    var cues: [Cue] = []
    var resolveColorHex: (Cue) -> String? = { _ in nil }
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }
    var engine: PlayerEngine?

    @State private var peaks: [Float]?
    @State private var failed = false
    @State private var loadedDuration: TimeInterval = 0
    @State private var scrub = ScrubController()
    @State private var seekTask: Task<Void, Never>?
    @State var zoom = WaveformZoomController()
    @State var verticalZoom = WaveformVerticalZoomController()
    @State var scrollOffset: CGFloat = 0
    @State private var leadingAnchor: Int? = 0
    @State var pinchBaseline: CGFloat = 1
    @State var viewportWidth: CGFloat = 0
    @State private var isProgrammaticAnchor = false
    @State var isHoveringWaveform = false
    @State private var hasShownFirstLaunchHint = false

    private static let maxAnchorCount = 200

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
        .task(id: asset.url) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .waveformZoomIn)) { _ in
            applyZoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waveformZoomOut)) { _ in
            applyZoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waveformZoomReset)) { _ in
            applyZoomReset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waveformVerticalZoomIn)) { _ in
            verticalZoom.zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waveformVerticalZoomOut)) { _ in
            verticalZoom.zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waveformVerticalZoomReset)) { _ in
            verticalZoom.reset()
        }
    }

    @ViewBuilder
    private func loaded(peaks: [Float]) -> some View {
        ZStack(alignment: .bottomTrailing) {
            waveformBody(peaks: peaks)
            verticalRail
            horizontalRail
        }
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHoveringWaveform = hovering
        }
        .onAppear {
            guard !hasShownFirstLaunchHint else { return }
            hasShownFirstLaunchHint = true
            isHoveringWaveform = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isHoveringWaveform = false
            }
        }
    }

    @ViewBuilder
    private func waveformBody(peaks: [Float]) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let contentWidth = max(width * zoom.zoom, width)

            ScrollView(.horizontal, showsIndicators: zoom.zoom > 1) {
                ZStack(alignment: .topLeading) {
                    WaveformView(peaks: peaks, verticalZoom: verticalZoom.zoom)
                    if loadedDuration > 0 {
                        CueMarkersOverlay(
                            cues: cues,
                            duration: loadedDuration,
                            resolveColorHex: resolveColorHex,
                            onSeek: onSeek,
                            onRetime: onRetime
                        )
                    }
                    if let engine, loadedDuration > 0 {
                        WaveformPlayheadLayer(
                            engine: engine,
                            duration: loadedDuration,
                            scrub: $scrub,
                            seekTask: $seekTask,
                            zoom: zoom,
                            viewportWidth: width,
                            scrollOffset: scrollOffset,
                            applyAutoFollow: applyAutoFollow
                        )
                    }
                    if zoom.zoom > 1 && loadedDuration > 0 {
                        anchorRail(contentWidth: contentWidth)
                    }
                }
                .frame(width: contentWidth, height: proxy.size.height, alignment: .leading)
            }
            .scrollPosition(id: $leadingAnchor, anchor: .leading)
            .scrollDisabled(zoom.zoom <= 1)
            .gesture(magnifyGesture(viewportWidth: width))
            .onChange(of: leadingAnchor) { _, new in
                if isProgrammaticAnchor {
                    isProgrammaticAnchor = false
                    return
                }
                guard zoom.zoom > 1, let new, loadedDuration > 0 else { return }
                let pxPerAnchor = contentWidth / CGFloat(anchorCount())
                scrollOffset = CGFloat(new) * pxPerAnchor
            }
            .onAppear { viewportWidth = width }
            .onChange(of: width) { _, new in viewportWidth = new }
        }
    }

    private func anchorRail(contentWidth: CGFloat) -> some View {
        let count = anchorCount()
        let segmentWidth = contentWidth / CGFloat(count)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Color.clear
                    .frame(width: segmentWidth, height: 1)
                    .id(index)
            }
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }

    private func anchorCount() -> Int {
        let raw = max(Int(loadedDuration.rounded(.up)), 1)
        return min(raw, Self.maxAnchorCount)
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
                syncAnchorFromOffset(viewportWidth: viewportWidth)
            }
            .onEnded { _ in
                pinchBaseline = zoom.zoom
            }
    }

    private func applyZoomIn() {
        mutateZoom { width, offset in
            zoom.zoomIn(viewportWidth: width, scrollOffset: &offset)
        }
    }

    private func applyZoomOut() {
        mutateZoom { width, offset in
            zoom.zoomOut(viewportWidth: width, scrollOffset: &offset)
        }
    }

    func applyZoomReset() {
        var offset = scrollOffset
        zoom.reset(scrollOffset: &offset)
        scrollOffset = offset
        isProgrammaticAnchor = true
        leadingAnchor = 0
        pinchBaseline = 1
    }

    private func mutateZoom(_ block: (CGFloat, inout CGFloat) -> Void) {
        guard viewportWidth > 0 else { return }
        var offset = scrollOffset
        block(viewportWidth, &offset)
        scrollOffset = offset
        pinchBaseline = zoom.zoom
        syncAnchorFromOffset(viewportWidth: viewportWidth)
    }

    func syncAnchorFromOffset(viewportWidth: CGFloat) {
        guard zoom.zoom > 1, loadedDuration > 0 else {
            isProgrammaticAnchor = true
            leadingAnchor = 0
            return
        }
        let contentWidth = viewportWidth * zoom.zoom
        let pxPerAnchor = contentWidth / CGFloat(anchorCount())
        isProgrammaticAnchor = true
        leadingAnchor = max(Int((scrollOffset / pxPerAnchor).rounded()), 0)
    }

    private func applyAutoFollow(targetOffset: CGFloat, viewportWidth: CGFloat) {
        scrollOffset = targetOffset
        guard zoom.zoom > 1 else { return }
        let contentWidth = viewportWidth * zoom.zoom
        let pxPerAnchor = contentWidth / CGFloat(anchorCount())
        isProgrammaticAnchor = true
        leadingAnchor = max(Int((targetOffset / pxPerAnchor).rounded()), 0)
    }

    private func load() async {
        peaks = nil
        failed = false
        var resetOffset = scrollOffset
        zoom.reset(scrollOffset: &resetOffset)
        scrollOffset = resetOffset
        verticalZoom.reset()
        if leadingAnchor != 0 {
            isProgrammaticAnchor = true
            leadingAnchor = 0
        }
        pinchBaseline = 1

        let cache = WaveformCache.shared
        let target = resolution
        let url = asset.url

        do {
            let hash: String? = await Task.detached(priority: .userInitiated) {
                try? WaveformCache.fileHash(url)
            }.value

            if Task.isCancelled { return }

            let cmDuration = try await asset.load(.duration)
            loadedDuration = CMTimeGetSeconds(cmDuration)

            if let hash, let cached = cache.read(assetHash: hash, resolution: target) {
                peaks = cached
                return
            }

            let generated = try await WaveformGenerator.peaks(for: asset, resolution: target)
            if Task.isCancelled { return }
            peaks = generated

            if let hash {
                Task.detached(priority: .background) {
                    try? cache.write(generated, assetHash: hash, resolution: target)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}

extension Notification.Name {
    static let waveformZoomIn = Notification.Name("OnlyCue.waveformZoomIn")
    static let waveformZoomOut = Notification.Name("OnlyCue.waveformZoomOut")
    static let waveformZoomReset = Notification.Name("OnlyCue.waveformZoomReset")
    static let waveformVerticalZoomIn = Notification.Name("OnlyCue.waveformVerticalZoomIn")
    static let waveformVerticalZoomOut = Notification.Name("OnlyCue.waveformVerticalZoomOut")
    static let waveformVerticalZoomReset = Notification.Name("OnlyCue.waveformVerticalZoomReset")
}
