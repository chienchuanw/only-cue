import AVFoundation

/// One waveform sample bucket covering a fixed wall-clock slice (default 10 ms).
///
/// Carries BOTH statistics the renderer needs and stores them **un-normalized**:
/// - `peak` — the largest `|sample|` in the slice, for finding transients when
///   zoomed in (issue #729: place cues on the sharpest beat).
/// - `rms` — root-mean-square energy, for a loudness-faithful overview that a
///   brickwall master can't collapse into a solid block (#632).
///
/// Per-file normalization is deliberately NOT applied here — it moves to render
/// time (#734) so progressive streaming stays self-consistent.
struct WaveformBucket: Equatable, Sendable {
    var peak: Float
    var rms: Float
}

extension WaveformBucket {

    /// Below this peak the buckets are treated as silence and left flat (mirrors
    /// `WaveformGenerator`'s silence floor, ≈ −80 dBFS): avoids amplifying the
    /// noise floor and dividing by zero when the render-time normalizer
    /// (`WaveformView.normalizedEnvelope`) divides by the loaded peak-max.
    static let silenceFloor: Float = 1e-4
}

extension WaveformGenerator {

    /// Analysis sample rate for the bucket engine. Far below 44.1 kHz because a
    /// 10 ms RMS/peak envelope needs nothing near full fidelity — this cuts both
    /// decode and per-sample iteration ~5.5× on long files (#729 spec §2).
    static let analysisSampleRate: Double = 8000

    /// Default bucket width in milliseconds (#729 spec §3).
    static let defaultBucketMillis = 10

    /// Int16 → normalized Float divisor (full-scale = 1.0).
    private static let sampleScale = Float(Int16.max)

    /// Collects the full bucket array by draining `bucketStream`. Convenience for
    /// callers that don't need progressive delivery.
    static func buckets(
        for asset: AVAsset,
        bucketMillis: Int = defaultBucketMillis,
        excludingChannel: Int? = nil
    ) async throws -> [WaveformBucket] {
        var latest: [WaveformBucket] = []
        for try await snapshot in bucketStream(
            for: asset, bucketMillis: bucketMillis, excludingChannel: excludingChannel
        ) {
            latest = snapshot
        }
        return latest
    }

    /// Streams the growing bucket array as decoding progresses: each element is
    /// the full accumulated snapshot so far, so a consumer can paint a partial
    /// waveform immediately (#729 spec §6). Throttling the yield cadence is the
    /// consumer's concern (#733); this producer yields once per decoded buffer.
    static func bucketStream(
        for asset: AVAsset,
        bucketMillis: Int = defaultBucketMillis,
        excludingChannel: Int? = nil
    ) -> AsyncThrowingStream<[WaveformBucket], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await produceBuckets(
                        asset: asset,
                        bucketMillis: bucketMillis,
                        excludingChannel: excludingChannel,
                        onSnapshot: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func produceBuckets(
        asset: AVAsset,
        bucketMillis: Int,
        excludingChannel: Int?,
        onSnapshot: ([WaveformBucket]) -> Void
    ) async throws {
        let framesPerBucket = max(Int(analysisSampleRate * Double(bucketMillis) / 1000), 1)

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            // No audio: a flat envelope of the duration-derived length.
            let count = try await bucketCount(asset: asset, bucketMillis: bucketMillis)
            onSnapshot(Array(repeating: WaveformBucket(peak: 0, rms: 0), count: count))
            return
        }

        let totalChannels = try await sourceChannelCount(track: track)
        let excluded = excludingChannel.flatMap { $0 >= 0 && $0 < totalChannels && totalChannels > 1 ? $0 : nil }
        // Exclusion needs every channel interleaved; otherwise let the reader
        // downmix to mono so the loop stays a flat sample scan.
        let readerChannels = excluded == nil ? 1 : totalChannels

        let reader = try makeReader(
            asset: asset, track: track, channels: readerChannels, sampleRate: analysisSampleRate
        )
        guard reader.startReading(),
              let output = reader.outputs.first as? AVAssetReaderTrackOutput else {
            throw WaveformError.readerFailed
        }

        var accumulator = BucketAccumulator(framesPerBucket: framesPerBucket)
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            ingest(buffer, into: &accumulator, readerChannels: readerChannels, excluding: excluded)
            CMSampleBufferInvalidate(buffer)
            onSnapshot(accumulator.buckets)
        }
        if reader.status == .failed { throw WaveformError.readerFailed }
        accumulator.finalizeTail()
        onSnapshot(accumulator.buckets)
    }

    /// Copies the interleaved Int16 block and feeds it to `accumulator`. When
    /// `excluded` is nil the reader already downmixed to mono, so every sample is
    /// one frame; otherwise every `readerChannels`-stride is a frame and only the
    /// non-excluded channels contribute.
    private static func ingest(
        _ buffer: CMSampleBuffer,
        into accumulator: inout BucketAccumulator,
        readerChannels: Int,
        excluding excluded: Int?
    ) {
        withInt16Samples(of: buffer) { samples in
            if excluded == nil {
                for sample in samples {
                    accumulator.addSample(Float(sample) / sampleScale)
                    accumulator.endFrame()
                }
            } else {
                var frameStart = samples.startIndex
                while frameStart < samples.endIndex {
                    for channel in 0..<readerChannels where channel != excluded {
                        let index = frameStart + channel
                        guard index < samples.endIndex else { break }
                        accumulator.addSample(Float(samples[index]) / sampleScale)
                    }
                    accumulator.endFrame()
                    frameStart += readerChannels
                }
            }
        }
    }

    /// Copies the interleaved Int16 PCM block out of `buffer` and hands it to
    /// `body` as a typed buffer — the shared unsafe-extraction prologue for both
    /// the downmix (`ingest`) and per-channel (`ingestChannels`) sample loops.
    private static func withInt16Samples(
        of buffer: CMSampleBuffer,
        _ body: (UnsafeBufferPointer<Int16>) -> Void
    ) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
        }
        data.withUnsafeBytes { raw in
            body(raw.bindMemory(to: Int16.self))
        }
    }

    /// Per-channel bucket generation: one un-normalized (peak+RMS) bucket array
    /// per non-excluded channel, in ascending channel order — the split-channel
    /// lanes (#720) rendered with the #734 dual envelope. Mono files, an
    /// out-of-range exclusion, or a collapsed kept-set fall back to a single
    /// downmix lane so callers treat the result uniformly; a file with no audio
    /// track yields one flat-silence lane.
    ///
    /// Deliberately NOT routed through `WaveformBucketCoordinator`: unlike the
    /// downmix, per-channel lanes are never prewarmed, so there is no concurrent
    /// production to coalesce — the coordinator would add machinery for nothing.
    static func channelBuckets(
        for asset: AVAsset,
        bucketMillis: Int = defaultBucketMillis,
        excludingChannel: Int?
    ) async throws -> [[WaveformBucket]] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            let count = try await bucketCount(asset: asset, bucketMillis: bucketMillis)
            return [Array(repeating: WaveformBucket(peak: 0, rms: 0), count: count)]
        }
        let totalChannels = try await sourceChannelCount(track: track)
        let keptChannels = keptChannelIndices(total: totalChannels, excluding: excludingChannel)
        guard totalChannels > 1, !keptChannels.isEmpty else {
            return [try await buckets(for: asset, bucketMillis: bucketMillis)]
        }
        return try await produceChannelBuckets(
            asset: asset,
            track: track,
            bucketMillis: bucketMillis,
            totalChannels: totalChannels,
            keptChannels: keptChannels
        )
    }

    /// Reads all `totalChannels` interleaved once and accumulates a separate
    /// peak+RMS bucket series per kept channel (parallel to `keptChannels`).
    private static func produceChannelBuckets(
        asset: AVAsset,
        track: AVAssetTrack,
        bucketMillis: Int,
        totalChannels: Int,
        keptChannels: [Int]
    ) async throws -> [[WaveformBucket]] {
        let framesPerBucket = max(Int(analysisSampleRate * Double(bucketMillis) / 1000), 1)
        let reader = try makeReader(
            asset: asset, track: track, channels: totalChannels, sampleRate: analysisSampleRate
        )
        guard reader.startReading(),
              let output = reader.outputs.first as? AVAssetReaderTrackOutput else {
            throw WaveformError.readerFailed
        }
        var accumulators = keptChannels.map { _ in BucketAccumulator(framesPerBucket: framesPerBucket) }
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            ingestChannels(buffer, into: &accumulators, keptChannels: keptChannels, channelCount: totalChannels)
            CMSampleBufferInvalidate(buffer)
        }
        if reader.status == .failed { throw WaveformError.readerFailed }
        for index in accumulators.indices { accumulators[index].finalizeTail() }
        return accumulators.map(\.buckets)
    }

    /// Feeds each kept channel's sample of every interleaved frame to its own
    /// accumulator, advancing all accumulators one frame in lockstep so the lanes
    /// share one time base.
    private static func ingestChannels(
        _ buffer: CMSampleBuffer,
        into accumulators: inout [BucketAccumulator],
        keptChannels: [Int],
        channelCount: Int
    ) {
        withInt16Samples(of: buffer) { samples in
            var frameStart = samples.startIndex
            while frameStart < samples.endIndex {
                for (index, channel) in keptChannels.enumerated() {
                    let sampleIndex = frameStart + channel
                    guard sampleIndex < samples.endIndex else { break }
                    accumulators[index].addSample(Float(samples[sampleIndex]) / sampleScale)
                }
                for index in accumulators.indices { accumulators[index].endFrame() }
                frameStart += channelCount
            }
        }
    }

    private static func bucketCount(asset: AVAsset, bucketMillis: Int) async throws -> Int {
        let duration = try await asset.load(.duration)
        let seconds = max(CMTimeGetSeconds(duration), 0)
        return max(Int((seconds * 1000 / Double(bucketMillis)).rounded(.up)), 0)
    }
}

/// Accumulates per-bucket peak (max |sample|) and RMS (root-mean-square over all
/// contributing samples). `framesPerBucket` counts frames so the time axis is
/// independent of channel count; RMS divides by the true contributing-sample
/// count so mono and multi-channel-exclusion paths stay on the same scale.
private struct BucketAccumulator {

    let framesPerBucket: Int
    private(set) var buckets: [WaveformBucket] = []
    private var frameCount = 0
    private var sampleCount = 0
    private var sumSquares: Float = 0
    private var maxAbs: Float = 0

    init(framesPerBucket: Int) {
        self.framesPerBucket = framesPerBucket
    }

    mutating func addSample(_ value: Float) {
        sumSquares += value * value
        let magnitude = abs(value)
        if magnitude > maxAbs { maxAbs = magnitude }
        sampleCount += 1
    }

    mutating func endFrame() {
        frameCount += 1
        if frameCount >= framesPerBucket { closeBucket() }
    }

    mutating func finalizeTail() {
        if frameCount > 0 { closeBucket() }
    }

    private mutating func closeBucket() {
        let rms = sampleCount > 0 ? (sumSquares / Float(sampleCount)).squareRoot() : 0
        buckets.append(WaveformBucket(peak: maxAbs, rms: rms))
        frameCount = 0
        sampleCount = 0
        sumSquares = 0
        maxAbs = 0
    }
}
