import AVFoundation

enum WaveformError: Error, Equatable {
    case readerFailed
}

enum WaveformGenerator {

    static func peaks(for asset: AVAsset, resolution: Int, excludingChannel: Int? = nil) async throws -> [Float] {
        guard resolution > 0 else { return [] }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return [Float](repeating: 0, count: resolution)
        }
        if let excluded = excludingChannel {
            return try await musicOnlyPeaks(
                asset: asset, track: track, resolution: resolution, excluding: excluded
            )
        }
        return try await monoDownmixPeaks(asset: asset, track: track, resolution: resolution)
    }

    /// Original single-channel (downmix) path. Behavior and output are
    /// byte-identical to the pre-#715 implementation.
    private static func monoDownmixPeaks(
        asset: AVAsset,
        track: AVAssetTrack,
        resolution: Int
    ) async throws -> [Float] {
        let reader = try makeReader(asset: asset, track: track, channels: 1)
        guard reader.startReading() else { throw WaveformError.readerFailed }
        guard let output = reader.outputs.first as? AVAssetReaderTrackOutput else {
            throw WaveformError.readerFailed
        }
        let totalSamples = try await estimatedSampleCount(asset: asset, resolution: resolution)
        var accumulator = RMSAccumulator(
            resolution: resolution,
            samplesPerBucket: max(totalSamples / resolution, 1)
        )
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try accumulator.ingest(sampleBuffer: buffer)
            CMSampleBufferInvalidate(buffer)
        }
        if reader.status == .failed { throw WaveformError.readerFailed }
        return normalized(accumulator.finalize())
    }

    /// Channel-exclusion path: read all N channels interleaved as Int16, then
    /// sum only the non-excluded channels into each RMS bucket. Falls back to
    /// the mono downmix when the file is mono or the index is out of range.
    private static func musicOnlyPeaks(
        asset: AVAsset,
        track: AVAssetTrack,
        resolution: Int,
        excluding excluded: Int
    ) async throws -> [Float] {
        let channelCount = try await sourceChannelCount(track: track)
        guard channelCount > 1, excluded >= 0, excluded < channelCount else {
            return try await monoDownmixPeaks(asset: asset, track: track, resolution: resolution)
        }
        let reader = try makeReader(asset: asset, track: track, channels: channelCount)
        guard reader.startReading() else { throw WaveformError.readerFailed }
        guard let output = reader.outputs.first as? AVAssetReaderTrackOutput else {
            throw WaveformError.readerFailed
        }
        let totalSamples = try await estimatedSampleCount(asset: asset, resolution: resolution)
        var accumulator = RMSAccumulator(
            resolution: resolution,
            samplesPerBucket: max(totalSamples / resolution, 1),
            musicChannelsPerFrame: channelCount - 1
        )
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try accumulator.ingest(sampleBuffer: buffer, channelCount: channelCount, excludingChannel: excluded)
            CMSampleBufferInvalidate(buffer)
        }
        if reader.status == .failed { throw WaveformError.readerFailed }
        return normalized(accumulator.finalize())
    }

    private static let outputSampleRate: Double = 44100

    /// Below this RMS level (≈ −80 dBFS) the file is treated as silence and left
    /// flat — this keeps truly-silent input at zero and avoids amplifying the
    /// noise floor (and dividing by zero). Any audible content is scaled so its
    /// loudest bucket reaches 1.0, so quiet files reveal their shape and loud
    /// files stop saturating into a solid block (issues #538, #632).
    private static let silenceFloor: Float = 1e-4

    private static func normalized(_ peaks: [Float]) -> [Float] {
        guard let maxPeak = peaks.max(), maxPeak > silenceFloor else { return peaks }
        return peaks.map { $0 / maxPeak }
    }

    private static func makeReader(
        asset: AVAsset,
        track: AVAssetTrack,
        channels: Int
    ) throws -> AVAssetReader {
        let reader = try AVAssetReader(asset: asset)
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.outputSampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        // Above stereo, AVAssetReader requires a channel layout — use the same
        // discrete (unpositioned) layout that AudioSampleReader uses.
        if channels > 2 {
            settings[AVChannelLayoutKey] = discreteLayoutData(channels: channels)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        return reader
    }

    /// Discrete (unpositioned) AudioChannelLayout data, matching the helper in
    /// `AudioSampleReader` so both use the same convention for >2 ch files.
    private static func discreteLayoutData(channels: Int) -> Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    /// The number of channels in `track`'s first format description, or 1 when
    /// the count cannot be determined (safe fallback: mono downmix).
    private static func sourceChannelCount(track: AVAssetTrack) async throws -> Int {
        let descriptions: [CMFormatDescription]
        do {
            descriptions = try await track.load(.formatDescriptions)
        } catch {
            return 1
        }
        guard let basic = descriptions.first?.audioStreamBasicDescription else { return 1 }
        return max(Int(basic.mChannelsPerFrame), 1)
    }

    private static func estimatedSampleCount(asset: AVAsset, resolution: Int) async throws -> Int {
        let duration = try await asset.load(.duration)
        let totalSeconds = max(CMTimeGetSeconds(duration), 0.001)
        return max(Int(totalSeconds * Self.outputSampleRate), resolution)
    }
}

/// Accumulates per-bucket **RMS** (root-mean-square energy), not peak. A loud,
/// brickwall-limited master pins almost every bucket's peak at full scale, so a
/// peak envelope collapses into a flat block with no visible dynamics; RMS
/// tracks audible loudness and keeps the song's structure legible (#632).
private struct RMSAccumulator {

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
