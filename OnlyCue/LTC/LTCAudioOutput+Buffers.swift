import AVFoundation

/// Pure buffer-building helpers for `LTCAudioOutput`. Lives in its own file so
/// the core engine file stays under the 400-line budget; all helpers here are
/// `static` and stateless, exercised directly by `LTCAudioOutputTests`.
extension LTCAudioOutput {

    /// A deinterleaved 32-bit-float format with `channelCount` channels in a
    /// discrete (non-standard) layout — `AVAudioFormat`'s simple initializers
    /// refuse channel counts without a standard `AVAudioChannelLayout` (3, 5, …),
    /// so use an explicit discrete layout. `nil` only for `channelCount < 1`.
    static func renderFormat(channelCount: Int, sampleRate: Double) -> AVAudioFormat? {
        guard channelCount >= 1, sampleRate > 0 else { return nil }
        guard let layout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelCount)
        ) else { return nil }
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout
        )
    }

    /// Build a multichannel float PCM buffer placing each `(samples, channel)`
    /// entry on its channel of `format` and silence on every other channel.
    /// Out-of-range channel indices clamp into bounds (a later entry on the same
    /// channel overwrites an earlier one). All `samples` arrays must share the
    /// same non-zero length.
    static func makeBuffer(
        channels: [(samples: [Float], channel: Int)], format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let frameCount = channels.first?.samples.count, frameCount > 0,
              channels.allSatisfy({ $0.samples.count == frameCount }),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let destinations = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channelCount = Int(format.channelCount)
        for index in 0..<channelCount { destinations[index].update(repeating: 0, count: frameCount) }
        for (samples, channel) in channels {
            let target = min(max(0, channel), channelCount - 1)
            samples.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { destinations[target].update(from: base, count: frameCount) }
            }
        }
        return buffer
    }

    /// Single mono-on-one-channel form — thin wrapper over `makeBuffer(channels:format:)`
    /// for the LTC pump.
    static func makeBuffer(monoSamples: [Float], format: AVAudioFormat, channel: Int) -> AVAudioPCMBuffer? {
        makeBuffer(channels: [(samples: monoSamples, channel: channel)], format: format)
    }

    /// When `isMuted` is true, returns a zero-filled array the same length as
    /// `samples`; otherwise returns `samples` unchanged. The render path uses
    /// this to silence the LTC channel without stopping the encoder.
    static func mutedSamples(_ samples: [Float], isMuted: Bool) -> [Float] {
        isMuted ? [Float](repeating: 0, count: samples.count) : samples
    }

    /// How many more buffers to schedule to reach `target` given the current
    /// `outstanding` lead.
    static func buffersToSchedule(outstanding: Int, target: Int) -> Int {
        max(0, target - max(0, outstanding))
    }
}
