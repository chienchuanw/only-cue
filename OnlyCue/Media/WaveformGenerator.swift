import AVFoundation

enum WaveformError: Error, Equatable {
    case readerFailed
}

enum WaveformGenerator {

    /// The true channel indices the split view renders as lanes, in ascending
    /// order — lets a caller key each lane's cache entry by its TRUE
    /// (exclusion-independent) channel index. `nil` for mono / collapsed-to-
    /// downmix files, where no per-channel index applies (don't per-channel cache).
    static func keptChannelIndices(for asset: AVAsset, excludingChannel: Int?) async throws -> [Int]? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let channelCount = try await sourceChannelCount(track: track)
        guard channelCount > 1 else { return nil }
        let kept = keptChannelIndices(total: channelCount, excluding: excludingChannel)
        return kept.isEmpty ? nil : kept
    }

    /// Returns channel indices to keep, in ascending order, optionally omitting
    /// one. Shared by `keptChannelIndices(for:excludingChannel:)` and the bucket
    /// engine's per-channel path (`WaveformBucketGenerator.channelBuckets`).
    static func keptChannelIndices(total: Int, excluding: Int?) -> [Int] {
        guard let excl = excluding, excl >= 0, excl < total else { return Array(0..<total) }
        return (0..<total).filter { $0 != excl }
    }

    /// Internal (not private) so the #732 bucket engine
    /// (`WaveformBucketGenerator.swift`) can build a reader at its analysis
    /// sample rate. There is no default: the only callers are the bucket engine's
    /// downmix and per-channel paths, which always pass `analysisSampleRate`.
    static func makeReader(
        asset: AVAsset,
        track: AVAssetTrack,
        channels: Int,
        sampleRate: Double
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
}
