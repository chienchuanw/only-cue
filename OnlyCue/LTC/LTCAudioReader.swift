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
    /// The first *corroborated* channel wins (see `isCorroborated`); a channel
    /// that yielded only an uncorroborated frame is held as a fallback and
    /// returned if no channel does better. Returns an empty array when the file
    /// carries no LTC, which is a real answer worth caching, not a failure.
    ///
    /// Throws `CancellationError` if the enclosing task is cancelled — the user
    /// switching clips mid-scan. Callers must not cache a cancelled result.
    static func detectTimecodes(
        from url: URL,
        windows: [TimeInterval] = scanWindows
    ) async throws -> [LTCDecoder.DecodedFrame] {
        let channels = max(1, try await AudioSampleReader.channelCount(of: url))
        var fallback: [LTCDecoder.DecodedFrame] = []
        for window in windows {
            try Task.checkCancellation()
            // One read per window, sliced per channel in memory: reading each
            // channel separately would decode the whole multichannel span N
            // times, which on a compressed 8-channel delivery mix is the
            // difference between one decode and sixteen.
            let interleaved = try await AudioSampleReader.readInterleavedSamples(
                from: url, channels: channels, range: 0...window
            )
            for channel in 0..<channels {
                try Task.checkCancellation()
                let samples = AudioSampleReader.channel(channel, of: channels, in: interleaved)
                let decoded = LTCDecoder.decode(samples: samples, sampleRate: sampleRate)
                if isCorroborated(decoded) { return decoded }
                if fallback.isEmpty { fallback = decoded }
            }
        }
        return fallback
    }

    /// Whether `frames` are trustworthy enough to relabel the transport `FILE`
    /// and anchor the whole readout on `frames.first`.
    ///
    /// A single frame isn't: sync word + parity + BCD can all line up by chance
    /// somewhere in minutes of programme audio across every channel, and one
    /// spurious hit would re-base every displayed timecode. Two consecutive
    /// frame numbers can't plausibly be luck.
    static func isCorroborated(_ frames: [LTCDecoder.DecodedFrame]) -> Bool {
        guard frames.count >= 2 else { return false }
        return zip(frames, frames.dropFirst()).contains { previous, next in
            next.timecode.frameCount == previous.timecode.frameCount + 1
        }
    }
}
