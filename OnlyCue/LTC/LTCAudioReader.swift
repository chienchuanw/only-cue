import AVFoundation

enum LTCAudioReaderError: Error, Equatable {
    /// The file has no audio track to read LTC from.
    case noAudioTrack
    /// `AVAssetReader` failed to start or aborted mid-read.
    case readerFailed
}

/// Reads a media file's first audio track as mono `Float` PCM and (optionally)
/// decodes the LTC striped onto it — the front door for `LTCDecoder` when the
/// timecode comes from an imported file rather than the generator. Down-mixes to
/// mono and resamples to a fixed rate so the decoder's bit-period maths stay
/// well-conditioned.
enum LTCAudioReader {

    /// Sample rate of the mono stream handed to the decoder. 48 kHz keeps
    /// 24 / 25 / 30 fps LTC at an integer (or near-integer) samples-per-half-bit.
    static let sampleRate: Double = 48_000

    /// The first audio track of `url`, down-mixed to mono `Float` PCM at
    /// `sampleRate`.
    static func readMonoSamples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw LTCAudioReaderError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
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
        guard reader.startReading() else { throw LTCAudioReaderError.readerFailed }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            appendFloatSamples(from: buffer, into: &samples)
            CMSampleBufferInvalidate(buffer)
        }
        if reader.status == .failed { throw LTCAudioReaderError.readerFailed }
        return samples
    }

    /// Decode every well-formed LTC frame striped onto `url`'s first audio track.
    static func decodeTimecodes(from url: URL) async throws -> [LTCDecoder.DecodedFrame] {
        LTCDecoder.decode(samples: try await readMonoSamples(from: url), sampleRate: sampleRate)
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
