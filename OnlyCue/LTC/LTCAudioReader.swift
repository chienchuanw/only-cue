import AVFoundation

/// Errors surfaced when reading LTC off a media file. Kept as an alias of
/// `AudioSampleReader.Error` so callers / tests that reference `LTCAudioReaderError`
/// keep working after the `AVAssetReader` glue was factored out into `AudioSampleReader`.
typealias LTCAudioReaderError = AudioSampleReader.Error

/// Reads a media file's first audio track and decodes the LTC striped onto it —
/// the front door for `LTCDecoder` when the timecode comes from an imported file
/// rather than the generator. Thin wrapper over `AudioSampleReader`.
enum LTCAudioReader {

    /// Sample rate of the mono stream handed to the decoder.
    static let sampleRate: Double = AudioSampleReader.sampleRate

    /// The first audio track of `url`, down-mixed to mono `Float` PCM at `sampleRate`.
    /// `maxSeconds` (when > 0) caps how much is read — enough to detect striped LTC
    /// without pulling an hour-long file into memory.
    static func readMonoSamples(from url: URL, maxSeconds: TimeInterval = 0) async throws -> [Float] {
        try await AudioSampleReader.readMonoSamples(from: url, range: maxSeconds > 0 ? 0...maxSeconds : nil)
    }

    /// Decode the LTC frames striped onto `url`'s first audio track, reading at most
    /// `maxSeconds` of audio (default 10 s — plenty for an anchor frame; LTC is linear
    /// so a `StripedTimecodeTrack` extrapolates the rest). Pass `maxSeconds: 0` to read
    /// the whole track.
    static func decodeTimecodes(from url: URL, maxSeconds: TimeInterval = 10) async throws -> [LTCDecoder.DecodedFrame] {
        LTCDecoder.decode(samples: try await readMonoSamples(from: url, maxSeconds: maxSeconds), sampleRate: sampleRate)
    }
}
