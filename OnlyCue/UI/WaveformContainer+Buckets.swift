import AVFoundation
import QuartzCore
import SwiftUI

/// Progressive bucket streaming for `WaveformContainer` (#733). Split into its
/// own file so `WaveformContainer.swift` stays under the `file_length` cap.
extension WaveformContainer {

    /// Consumes the coalesced bucket stream for this asset, repainting `peaks` at
    /// most every 16 ms (a progressive "still working" feel without flooding the
    /// UI), and returns the final bucket set. Normalization is applied on read via
    /// `normalizedRMS` (the #733 adapter; render-time normalization + the dual
    /// envelope arrive in #734). Runs on the MainActor (SwiftUI `View`), so each
    /// awaited resumption is safe to assign `@State` from.
    func streamBuckets(
        url: URL,
        bucketMillis: Int,
        excludingChannel: Int?,
        hash: String?
    ) async throws -> [WaveformBucket] {
        let key = WaveformBucketCoordinator.cacheKey(
            hash: hash, url: url, bucketMillis: bucketMillis, excludingChannel: excludingChannel
        )
        let stream = WaveformBucketCoordinator.shared.stream(for: key) {
            WaveformGenerator.bucketStream(
                for: AVURLAsset(url: url), bucketMillis: bucketMillis, excludingChannel: excludingChannel
            )
        }

        var latest: [WaveformBucket] = []
        var lastPaint = ContinuousClock.now
        for try await snapshot in stream {
            try Task.checkCancellation()
            latest = snapshot
            let now = ContinuousClock.now
            if now - lastPaint >= .milliseconds(16) {
                peaks = WaveformBucket.normalizedRMS(snapshot)
                lastPaint = now
            }
        }
        return latest
    }
}
