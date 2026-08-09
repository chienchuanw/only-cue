import AVFoundation

/// Accumulates per-bucket **RMS** (root-mean-square energy), not peak. A loud,
/// brickwall-limited master pins almost every bucket's peak at full scale, so a
/// peak envelope collapses into a flat block with no visible dynamics; RMS
/// tracks audible loudness and keeps the song's structure legible (#632).
///
/// This is the legacy fixed-resolution, pre-normalized accumulator for
/// `WaveformGenerator.peaks`. The #729 rollout adds a parallel time-based
/// peak+RMS engine (`WaveformBucketGenerator.swift`); this path is slated for
/// removal once the renderer moves to buckets (#734).
struct RMSAccumulator {

    let resolution: Int
    let samplesPerBucket: Int
    /// Number of contributing channels per frame (1 for the mono path, or
    /// `totalChannels - 1` for the music-only path). Used when normalising the
    /// RMS denominator so the scale is comparable across paths.
    ///
    /// **Denominator asymmetry note:** the mono `ingest(samples:)` helper divides
    /// mid-stream bucket closures by `samplesInBucket` alone and never reads this
    /// field (it is always 1 on the mono path). Only the multi-channel
    /// `ingest(interleavedSamples:...)` path uses `musicChannelsPerFrame` in its
    /// denominator. If a future refactor merges these two paths, the mid-stream
    /// bucket closure must NOT blindly apply `musicChannelsPerFrame` to the mono
    /// path — doing so would silently introduce a 2× denominator error there.
    let musicChannelsPerFrame: Int
    private(set) var peaks: [Float]
    private var bucketIndex = 0
    private var samplesInBucket = 0
    private var bucketSumSq: Float = 0

    init(resolution: Int, samplesPerBucket: Int, musicChannelsPerFrame: Int = 1) {
        self.resolution = resolution
        self.samplesPerBucket = samplesPerBucket
        self.musicChannelsPerFrame = max(musicChannelsPerFrame, 1)
        self.peaks = [Float](repeating: 0, count: resolution)
    }

    mutating func ingest(sampleBuffer: CMSampleBuffer) throws {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }
        data.withUnsafeBytes { rawBuffer in
            ingest(samples: rawBuffer.bindMemory(to: Int16.self))
        }
    }

    /// Multi-channel variant: reads `channelCount`-interleaved Int16 samples but
    /// contributes only the non-`excludedChannel` channels to the RMS buckets.
    /// `samplesPerBucket` is in units of *frames* (one frame = `channelCount`
    /// interleaved samples), which keeps the time axis identical to the mono path.
    mutating func ingest(
        sampleBuffer: CMSampleBuffer,
        channelCount: Int,
        excludingChannel excluded: Int
    ) throws {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }
        data.withUnsafeBytes { rawBuffer in
            ingest(
                interleavedSamples: rawBuffer.bindMemory(to: Int16.self),
                channelCount: channelCount,
                excludingChannel: excluded
            )
        }
    }

    /// Add one sample's squared value to the current bucket (per-channel path).
    /// Call `advanceFrame()` after processing all kept channels in a frame.
    mutating func ingestSingleSample(_ value: Float) {
        bucketSumSq += value * value
    }

    /// Close the current bucket if it is full after one interleaved frame has been
    /// contributed. `samplesInBucket` counts frames, matching the mono path.
    mutating func advanceFrame() {
        samplesInBucket += 1
        if samplesInBucket >= samplesPerBucket && bucketIndex < resolution {
            let denom = Float(samplesInBucket) * Float(musicChannelsPerFrame)
            peaks[bucketIndex] = (bucketSumSq / denom).squareRoot()
            bucketIndex += 1
            samplesInBucket = 0
            bucketSumSq = 0
        }
    }

    mutating func finalize() -> [Float] {
        if bucketIndex < resolution && samplesInBucket > 0 {
            // `musicChannelsPerFrame` is 1 on the mono path (see property note
            // above), so this formula is correct for both paths: on mono it
            // reduces to `samplesInBucket`; on the multi-channel path it divides
            // by frames × contributing-channels to obtain the true per-sample RMS.
            let denom = Float(samplesInBucket) * Float(musicChannelsPerFrame)
            peaks[bucketIndex] = (bucketSumSq / denom).squareRoot()
        }
        return peaks
    }

    private mutating func ingest(samples: UnsafeBufferPointer<Int16>) {
        for sample in samples {
            let value = Float(sample) / Float(Int16.max)
            bucketSumSq += value * value
            samplesInBucket += 1
            if samplesInBucket >= samplesPerBucket && bucketIndex < resolution {
                peaks[bucketIndex] = (bucketSumSq / Float(samplesInBucket)).squareRoot()
                bucketIndex += 1
                samplesInBucket = 0
                bucketSumSq = 0
            }
        }
    }

    /// Interleaved multi-channel variant: advances one *frame* at a time and
    /// sums only the non-excluded channels. `samplesInBucket` counts frames
    /// so the time axis stays aligned with the mono path's bucket boundaries.
    private mutating func ingest(
        interleavedSamples: UnsafeBufferPointer<Int16>,
        channelCount: Int,
        excludingChannel excluded: Int
    ) {
        var frameStart = interleavedSamples.startIndex
        while frameStart < interleavedSamples.endIndex {
            // Accumulate RMS energy from the music channels within this frame.
            for ch in 0..<channelCount where ch != excluded {
                let sampleIndex = frameStart + ch
                guard sampleIndex < interleavedSamples.endIndex else { break }
                let value = Float(interleavedSamples[sampleIndex]) / Float(Int16.max)
                bucketSumSq += value * value
            }
            samplesInBucket += 1
            if samplesInBucket >= samplesPerBucket && bucketIndex < resolution {
                let denom = Float(samplesInBucket) * Float(musicChannelsPerFrame)
                peaks[bucketIndex] = (bucketSumSq / denom).squareRoot()
                bucketIndex += 1
                samplesInBucket = 0
                bucketSumSq = 0
            }
            frameStart += channelCount
        }
    }
}
