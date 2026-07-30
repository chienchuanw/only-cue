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

    /// Scan windows, in seconds, tried in order. 10 s is enough for a file that
    /// starts on timecode and keeps the common case cheap; widening to 60 s
    /// covers a pre-roll, a countdown, or leading silence before the LTC starts.
    static let scanWindows: [TimeInterval] = [10, 60]

    /// Finds the LTC on `url` without being told where it is: each channel is
    /// decoded on its own — timecode is normally striped onto *one* channel of a
    /// delivery mix, where the down-mix `decodeTimecodes` reads would bury it
    /// under the programme audio — and the scan widens only if nothing is found.
    ///
    /// The first channel that decodes wins. Returns an empty array when the file
    /// carries no LTC, which is a real answer worth caching, not a failure.
    static func detectTimecodes(
        from url: URL,
        windows: [TimeInterval] = scanWindows
    ) async throws -> [LTCDecoder.DecodedFrame] {
        let channels = max(1, try await AudioSampleReader.channelCount(of: url))
        for window in windows {
            for channel in 0..<channels {
                let samples = try await AudioSampleReader.readSamples(
                    from: url, channel: channels == 1 ? nil : channel, range: 0...window
                )
                let decoded = LTCDecoder.decode(samples: samples, sampleRate: sampleRate)
                if !decoded.isEmpty { return decoded }
            }
        }
        return []
    }
}
