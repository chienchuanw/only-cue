import AVFoundation

/// Reads a media file's first audio track as mono `Float` PCM at a fixed rate —
/// the shared `AVAssetReader` glue used by both the LTC decoder (`LTCAudioReader`)
/// and the tempo analyzer. Down-mixing to mono + resampling to one rate keeps the
/// consumers' DSP maths well-conditioned and lets them ignore source channel
/// counts / sample rates entirely.
enum AudioSampleReader {

    enum Error: Swift.Error, Equatable {
        /// The file has no audio track.
        case noAudioTrack
        /// `AVAssetReader` failed to start or aborted mid-read.
        case readerFailed
    }

    /// 48 kHz mono: keeps 24 / 25 / 30 fps LTC at an integer-ish samples-per-half-bit
    /// and is plenty of resolution for tempo onset detection.
    static let sampleRate: Double = 48_000

    /// The first audio track of `url`, down-mixed to mono `Float` PCM at `sampleRate`.
    /// When `range` is given, only that span of the timeline is read (so analyzing one
    /// tempo section, or detecting striped LTC on an hour-long file, doesn't pull the
    /// whole track into memory).
    static func readMonoSamples(
        from url: URL,
        range: ClosedRange<TimeInterval>? = nil
    ) async throws -> [Float] {
        try await readInterleavedSamples(from: url, channels: 1, range: range)
    }

    /// How many channels `url`'s first audio track carries — the bound for
    /// `readInterleavedSamples(from:channels:range:)`. Zero when it can't be determined.
    static func channelCount(of url: URL) async throws -> Int {
        let track = try await firstAudioTrack(of: AVURLAsset(url: url))
        let descriptions: [CMFormatDescription]
        do { descriptions = try await track.load(.formatDescriptions) } catch { throw Error.readerFailed }
        guard let basic = descriptions.first?.audioStreamBasicDescription else { return 0 }
        return Int(basic.mChannelsPerFrame)
    }

    /// Every channel of `url`'s first audio track, interleaved, at `sampleRate`.
    ///
    /// This exists for LTC: timecode is striped onto *one* channel of a delivery
    /// mix, and summing that channel with the programme audio buries the biphase
    /// square wave the decoder reads zero crossings from. Consumers that don't
    /// care about channel identity — the tempo analyzer — keep using the
    /// down-mix. Read once through here and slice with `channel(_:of:in:)`
    /// rather than reading per channel, which would decode the whole
    /// multichannel track N times and throw away N−1 channels each pass.
    ///
    /// `channels` is passed in rather than probed so a caller that already knows
    /// it (from `channelCount(of:)`) doesn't pay for a second asset load; pass 1
    /// to get the down-mix.
    static func readInterleavedSamples(
        from url: URL,
        channels outputChannels: Int,
        range: ClosedRange<TimeInterval>? = nil
    ) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let track = try await firstAudioTrack(of: asset)
        // 0 when the duration is unknown or indefinite, which reads as "reserve
        // nothing" below rather than as a nonsense capacity.
        let loadedSeconds = CMTimeGetSeconds((try? await track.load(.timeRange))?.duration ?? .invalid)
        let trackSeconds = loadedSeconds.isFinite ? max(0, loadedSeconds) : 0

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw Error.readerFailed }
        if let range, range.upperBound > range.lowerBound {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                duration: CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 600)
            )
        }
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: outputChannels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        // Above stereo, `AVAssetReader` rejects a channel count with no layout.
        if outputChannels > 2 { settings[AVChannelLayoutKey] = discreteLayoutData(channels: outputChannels) }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw Error.readerFailed }

        var samples: [Float] = []
        if let range, range.upperBound > range.lowerBound {
            // Clamped to what the track actually holds: every file with no LTC
            // reaches the 60 s window, and most are shorter than that — the
            // returned array keeps whatever was reserved, so an unclamped
            // reserve would hold 92 MB for 8 MB of samples on exactly the files
            // the widened scan visits most.
            let available = max(0, trackSeconds - range.lowerBound)
            let seconds = min(range.upperBound - range.lowerBound, available)
            samples.reserveCapacity(Int(seconds * sampleRate) * outputChannels)
        }
        while let buffer = output.copyNextSampleBuffer() {
            // Decoding a 60 s × 8-channel window is the slow part of an LTC
            // scan; without this a cancelled scan (the user switching clips)
            // would still decode the whole window before anyone noticed.
            guard !Task.isCancelled else {
                CMSampleBufferInvalidate(buffer)
                reader.cancelReading()
                throw CancellationError()
            }
            appendFloatSamples(from: buffer, into: &samples)
            CMSampleBufferInvalidate(buffer)
        }
        reader.cancelReading()
        if reader.status == .failed { throw Error.readerFailed }
        return samples
    }

    /// One channel lifted out of an interleaved buffer, without re-reading the
    /// file. `channels == 1` passes the buffer straight through.
    static func channel(_ index: Int, of channels: Int, in interleaved: [Float]) -> [Float] {
        precondition(index >= 0 && index < channels, "channel \(index) is outside a \(channels)-channel buffer")
        guard channels > 1 else { return interleaved }
        return stride(from: index, to: interleaved.count, by: channels).map { interleaved[$0] }
    }

    private static func firstAudioTrack(of asset: AVURLAsset) async throws -> AVAssetTrack {
        let tracks: [AVAssetTrack]
        do { tracks = try await asset.loadTracks(withMediaType: .audio) } catch { throw Error.readerFailed }
        guard let track = tracks.first else { throw Error.noAudioTrack }
        return track
    }

    /// A discrete (unpositioned) channel layout — the honest description of a
    /// track whose channels are separate feeds rather than a surround mix.
    private static func discreteLayoutData(channels: Int) -> Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    private static func appendFloatSamples(from sampleBuffer: CMSampleBuffer, into samples: inout [Float]) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }
        var data = Data(count: length)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
        }
        data.withUnsafeBytes { raw in
            samples.append(contentsOf: raw.bindMemory(to: Float.self))
        }
    }
}
