import AVFoundation

/// Best-effort, background-priority cache warming so the user's first click on a
/// freshly-imported item hits a populated bucket cache (#733). Warms EVERY item
/// on import (甲), but with a bounded concurrency so importing a batch of large
/// files can't saturate CPU/disk. Production goes through
/// `WaveformBucketCoordinator`, so a foreground open of a still-warming file
/// attaches to the same decode instead of starting a second one.
///
/// Failures (missing file, stale bookmark, decode error) are swallowed; the
/// foreground load path in `WaveformContainer` surfaces them when it runs.
enum WaveformPrewarmer {

    static let defaultBucketMillis = WaveformGenerator.defaultBucketMillis

    /// Max files decoded at once. Keeps a batch import of large work tapes from
    /// pinning every core in the background.
    static let maxConcurrent = 3

    static func prewarm(items: [MediaItem], bucketMillis: Int = defaultBucketMillis) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()

            // Not `@Sendable`: this runs synchronously inside the task-group
            // closure and never escapes, so it can drive the mutable iterator and
            // the `inout group` directly. Marking it `@Sendable` would force those
            // captures across a concurrency boundary and fail the Swift-6 checks.
            func scheduleNext() -> Bool {
                guard let item = iterator.next() else { return false }
                group.addTask(priority: .background) {
                    await prewarmOne(item, bucketMillis: bucketMillis)
                }
                return true
            }

            for _ in 0..<maxConcurrent where scheduleNext() {}
            while await group.next() != nil { _ = scheduleNext() }
        }
    }

    private static func prewarmOne(_ item: MediaItem, bucketMillis: Int) async {
        guard let bookmark = try? Bookmarks.resolve(item.media.bookmarkData) else { return }
        let url = bookmark.url
        guard let hash = try? WaveformCache.fastFingerprint(url) else { return }
        if WaveformCache.shared.readBuckets(assetHash: hash, bucketMillis: bucketMillis) != nil {
            return
        }

        let key = WaveformBucketCoordinator.cacheKey(
            hash: hash, url: url, bucketMillis: bucketMillis, excludingChannel: nil
        )
        let stream = WaveformBucketCoordinator.shared.stream(for: key) {
            WaveformGenerator.bucketStream(for: AVURLAsset(url: url), bucketMillis: bucketMillis)
        }

        var latest: [WaveformBucket] = []
        do {
            for try await snapshot in stream { latest = snapshot }
        } catch {
            return
        }
        guard !latest.isEmpty else { return }
        try? WaveformCache.shared.writeBuckets(latest, assetHash: hash, bucketMillis: bucketMillis)
    }
}
