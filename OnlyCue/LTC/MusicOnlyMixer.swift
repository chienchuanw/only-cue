import AVFoundation

/// Pure channel-mix maths for the source-audio *music-only* mode: drop the
/// channel that carries striped LTC and center the surviving music onto every
/// output channel.
///
/// Split out from the realtime tap (`MusicOnlyTap`) so the sample maths is unit
/// testable without a live `AVPlayerItem`.
enum MusicOnlyMixer {

    /// Replaces every channel with the mean of the non-LTC channels, so the LTC
    /// channel's tone is gone and the surviving music is centered onto ALL
    /// channels. `channels` are deinterleaved per-channel sample arrays, all the
    /// same length. Returns `channels` unchanged (an identity copy) when there is
    /// nothing to do: channelCount <= 1, `ltcChannel` out of range, or no music
    /// channel would remain.
    ///
    /// Uses the *mean* (not the sum) of the music channels so a single surviving
    /// music channel returns at unchanged amplitude and multi-music does not clip.
    static func centered(channels: [[Float]], excludingChannel ltcChannel: Int) -> [[Float]] {
        let channelCount = channels.count
        guard channelCount > 1, ltcChannel >= 0, ltcChannel < channelCount else { return channels }

        let musicIndices = (0..<channelCount).filter { $0 != ltcChannel }
        guard !musicIndices.isEmpty else { return channels }

        let frameCount = channels[0].count
        let divisor = Float(musicIndices.count)
        var mix = [Float](repeating: 0, count: frameCount)
        for index in musicIndices {
            let channel = channels[index]
            for frame in 0..<frameCount { mix[frame] += channel[frame] }
        }
        for frame in 0..<frameCount { mix[frame] /= divisor }

        return Array(repeating: mix, count: channelCount)
    }

    /// In-place variant of `centered(channels:excludingChannel:)` operating on a
    /// float PCM buffer: rewrites every channel to the mean of the non-LTC
    /// channels. Handles both interleaved and non-interleaved float buffers.
    /// No-op when the buffer is not float32, channelCount <= 1, `ltcChannel` is
    /// out of range, or no music channel would remain.
    ///
    /// Reads the channels out into arrays, runs the shared `centered` maths, then
    /// writes them back — so the mean-of-non-LTC logic lives in exactly one place.
    static func applyInPlace(to buffer: AVAudioPCMBuffer, excludingChannel ltcChannel: Int) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let floatData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 1, frameCount > 0,
              ltcChannel >= 0, ltcChannel < channelCount else { return }

        if buffer.format.isInterleaved {
            let samples = floatData[0]
            var channels = [[Float]](repeating: [], count: channelCount)
            for channel in 0..<channelCount {
                channels[channel] = (0..<frameCount).map { samples[$0 * channelCount + channel] }
            }
            let mixed = centered(channels: channels, excludingChannel: ltcChannel)
            for channel in 0..<channelCount {
                for frame in 0..<frameCount { samples[frame * channelCount + channel] = mixed[channel][frame] }
            }
        } else {
            var channels = [[Float]](repeating: [], count: channelCount)
            for channel in 0..<channelCount {
                channels[channel] = Array(UnsafeBufferPointer(start: floatData[channel], count: frameCount))
            }
            let mixed = centered(channels: channels, excludingChannel: ltcChannel)
            for channel in 0..<channelCount {
                let dst = floatData[channel]
                for frame in 0..<frameCount { dst[frame] = mixed[channel][frame] }
            }
        }
    }
}
