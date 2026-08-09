import AVFoundation
import SwiftUI

/// Per-channel ("Split Channels") lane loading for `WaveformContainer` (#720).
/// Split into its own file so `WaveformContainer.swift` stays under the
/// `file_length`/`type_body_length` caps.
extension WaveformContainer {
    /// Populates `lanePeaks` with one normalized peak array per kept channel,
    /// served from the per-channel cache and regenerated on any miss.
    ///
    /// Cache keying: each lane is keyed by its TRUE channel index (via
    /// `WaveformCache.read/write(...channel:)`). True-index keying is
    /// exclusion-independent — channel N's peaks are the same no matter which
    /// other channel is the LTC track — so entries never collide across different
    /// `excludingChannel` values. Read and write use the SAME true-index keying,
    /// and a miss on ANY lane regenerates and rewrites the WHOLE set so a partial
    /// cache can never yield a mismatched lane.
    ///
    /// When the file is mono (or the kept set collapses to the single
    /// mono-downmix fallback), `keptChannelIndices` returns nil: there is no
    /// meaningful per-channel index, so the lane set is generated directly (one
    /// lane) without touching the per-channel cache.
    func loadLanes(hash: String?, resolution: Int, excludingChannel: Int?, cache: WaveformCache) async {
        let keptChannels: [Int]?
        do {
            keptChannels = try await WaveformGenerator.keptChannelIndices(
                for: asset,
                excludingChannel: excludingChannel
            )
        } catch is CancellationError {
            return
        } catch {
            failed = true
            return
        }
        if Task.isCancelled { return }

        // Cache hit path: all kept lanes present under their true-channel keys.
        if let hash, let kept = keptChannels {
            let cached = kept.map { cache.read(assetHash: hash, resolution: resolution, channel: $0) }
            if cached.allSatisfy({ $0 != nil }) {
                lanePeaks = cached.compactMap { $0 }
                return
            }
        }

        // Miss (or mono/unhashed): regenerate the whole set, then cache each lane
        // under its true channel index when we have both a hash and the indices.
        let generated: [[Float]]
        do {
            generated = try await WaveformGenerator.channelPeaks(
                for: asset,
                resolution: resolution,
                excludingChannel: excludingChannel
            )
        } catch is CancellationError {
            return
        } catch {
            failed = true
            return
        }
        if Task.isCancelled { return }
        lanePeaks = generated

        // Only cache when the generated lanes line up 1:1 with the derived true
        // channel indices (i.e. the true per-channel path, not the mono fallback).
        if let hash, let kept = keptChannels, kept.count == generated.count {
            Task.detached(priority: .background) {
                for (index, channel) in kept.enumerated() {
                    try? cache.write(generated[index], assetHash: hash, resolution: resolution, channel: channel)
                }
            }
        }
    }

    /// Persists the freshly-generated downmix / music-only bucket array to the v4
    /// bucket cache off the main actor — a no-op when the file hash is absent
    /// (#733). Extracted to keep `load()` under the `function_body_length` cap.
    func cacheBuckets(
        _ buckets: [WaveformBucket],
        hash: String?,
        bucketMillis: Int,
        excludingChannel: Int?,
        cache: WaveformCache
    ) {
        guard let hash, !buckets.isEmpty else { return }
        Task.detached(priority: .background) {
            try? cache.writeBuckets(
                buckets,
                assetHash: hash,
                bucketMillis: bucketMillis,
                excludingChannel: excludingChannel
            )
        }
    }
}
