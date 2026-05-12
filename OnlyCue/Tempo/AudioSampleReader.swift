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
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do { tracks = try await asset.loadTracks(withMediaType: .audio) } catch { throw Error.readerFailed }
        guard let track = tracks.first else { throw Error.noAudioTrack }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw Error.readerFailed }
        if let range, range.upperBound > range.lowerBound {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                duration: CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 600)
            )
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw Error.readerFailed }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            appendFloatSamples(from: buffer, into: &samples)
            CMSampleBufferInvalidate(buffer)
        }
        reader.cancelReading()
        if reader.status == .failed { throw Error.readerFailed }
        return samples
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
