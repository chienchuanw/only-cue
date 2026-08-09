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

    /// Per-channel peak generation: returns one normalized peak array per
    /// non-excluded channel, in ascending channel order. Mono files or an
    /// out-of-range `excludingChannel` fall back to a single-element array
    /// equal to `monoDownmixPeaks` so callers can treat the result uniformly.
    /// Each inner array has length `resolution`.
    static func channelPeaks(
        for asset: AVAsset,
        resolution: Int,
        excludingChannel: Int?
    ) async throws -> [[Float]] {
        guard resolution > 0 else { return [] }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return [[Float](repeating: 0, count: resolution)]
        }
        let channelCount = try await sourceChannelCount(track: track)
        guard channelCount > 1 else {
            return [try await monoDownmixPeaks(asset: asset, track: track, resolution: resolution)]
        }
        let keptChannels = keptChannelIndices(total: channelCount, excluding: excludingChannel)
        guard !keptChannels.isEmpty else {
            return [try await monoDownmixPeaks(asset: asset, track: track, resolution: resolution)]
        }
        return try await perChannelPeaks(
            asset: asset,
            track: track,
            resolution: resolution,
            channelCount: channelCount,
            keptChannels: keptChannels
        )
    }

    /// The true channel indices `channelPeaks` renders as lanes, in the same
    /// ascending order — lets a caller key each lane's cache entry by its TRUE
    /// (exclusion-independent) channel index. `nil` for mono / collapsed-to-
    /// downmix files, where no per-channel index applies (don't per-channel cache).
    static func keptChannelIndices(for asset: AVAsset, excludingChannel: Int?) async throws -> [Int]? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let channelCount = try await sourceChannelCount(track: track)
        guard channelCount > 1 else { return nil }
        let kept = keptChannelIndices(total: channelCount, excluding: excludingChannel)
        return kept.isEmpty ? nil : kept
    }

    /// Returns channel indices to keep, in ascending order, optionally omitting one.
    private static func keptChannelIndices(total: Int, excluding: Int?) -> [Int] {
        guard let excl = excluding, excl >= 0, excl < total else { return Array(0..<total) }
        return (0..<total).filter { $0 != excl }
    }

    /// Reads `channelCount` channels interleaved and accumulates a separate
    /// `RMSAccumulator` per entry in `keptChannels`. Returns one normalized
    /// peak array per kept channel, in the same order.
    private static func perChannelPeaks(
        asset: AVAsset,
        track: AVAssetTrack,
        resolution: Int,
        channelCount: Int,
        keptChannels: [Int]
    ) async throws -> [[Float]] {
        let reader = try makeReader(asset: asset, track: track, channels: channelCount)
        guard reader.startReading() else { throw WaveformError.readerFailed }
        guard let output = reader.outputs.first as? AVAssetReaderTrackOutput else {
            throw WaveformError.readerFailed
        }
        let totalSamples = try await estimatedSampleCount(asset: asset, resolution: resolution)
        let spb = max(totalSamples / resolution, 1)
        // Parallel arrays: keptChannels[i] ↔ accumulators[i].
        var accumulators = keptChannels.map { _ in
            RMSAccumulator(resolution: resolution, samplesPerBucket: spb, musicChannelsPerFrame: 1)
        }
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try ingestBuffer(buffer, into: &accumulators, keptChannels: keptChannels, channelCount: channelCount)
            CMSampleBufferInvalidate(buffer)
        }
        if reader.status == .failed { throw WaveformError.readerFailed }
        return accumulators.indices.map { idx in normalized(accumulators[idx].finalize()) }
    }

    /// Copies `buffer` and feeds each kept channel's sample to its accumulator.
    private static func ingestBuffer(
        _ buffer: CMSampleBuffer,
        into accumulators: inout [RMSAccumulator],
        keptChannels: [Int],
        channelCount: Int
    ) throws {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            var frameStart = samples.startIndex
            while frameStart < samples.endIndex {
                for (idx, ch) in keptChannels.enumerated() {
                    let si = frameStart + ch
                    guard si < samples.endIndex else { break }
                    accumulators[idx].ingestSingleSample(Float(samples[si]) / Float(Int16.max))
                }
                for idx in accumulators.indices { accumulators[idx].advanceFrame() }
                frameStart += channelCount
            }
        }
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

    /// Internal (not private) so the #732 bucket engine
    /// (`WaveformBucketGenerator.swift`) can build a reader at its own analysis
    /// sample rate. `sampleRate` defaults to the legacy 44.1 kHz so existing
    /// callers are unchanged.
    static func makeReader(
        asset: AVAsset,
        track: AVAssetTrack,
        channels: Int,
        sampleRate: Double = Self.outputSampleRate
    ) throws -> AVAssetReader {
        let reader = try AVAssetReader(asset: asset)
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
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
    /// Internal (not private) so the #732 bucket engine can reuse it.
    static func sourceChannelCount(track: AVAssetTrack) async throws -> Int {
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
