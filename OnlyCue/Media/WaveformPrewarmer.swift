import AVFoundation

/// Best-effort, background-priority cache warming so the user's first click on
/// a freshly-imported item hits a populated `WaveformCache`. Failures (missing
/// file, stale bookmark, decode error) are swallowed; the foreground load path
/// in `WaveformContainer` will surface them when it runs for real.
enum WaveformPrewarmer {

    static let defaultResolution = 512

    static func prewarm(items: [MediaItem], resolution: Int = defaultResolution) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask(priority: .background) {
                    await prewarmOne(item, resolution: resolution)
                }
            }
        }
    }

    private static func prewarmOne(_ item: MediaItem, resolution: Int) async {
        guard let bookmark = try? Bookmarks.resolve(item.media.bookmarkData) else { return }
        let url = bookmark.url
        guard let hash = try? WaveformCache.fileHash(url) else { return }
        if WaveformCache.shared.read(assetHash: hash, resolution: resolution) != nil {
            return
        }
        let asset = AVURLAsset(url: url)
        guard let peaks = try? await WaveformGenerator.peaks(for: asset, resolution: resolution) else { return }
        try? WaveformCache.shared.write(peaks, assetHash: hash, resolution: resolution)
    }
}
