import Foundation

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
}
