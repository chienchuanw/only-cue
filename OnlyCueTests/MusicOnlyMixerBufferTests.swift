import AVFoundation
import XCTest
@testable import OnlyCue

/// Buffer-level tests for `MusicOnlyMixer.applyInPlace(to:excludingChannel:)`, the
/// shared in-place transform used by both the plain-path (`MusicOnlyTap`) and the
/// LTC-output-path (`ProgramAudioTap`) music-only filters. Unlike the taps, an
/// `AVAudioPCMBuffer` can be built and filled with no audio device or engine, so
/// this exercises the real transform headlessly.
final class MusicOnlyMixerBufferTests: XCTestCase {

    // MARK: - Buffer helpers

    /// A discrete N-channel float32 format. A plain `AVAudioFormat(commonFormat:…
    /// channels:…)` returns nil for channel counts without a standard layout
    /// (e.g. 3), so build an explicit discrete layout that works for any count.
    private func makeFormat(channelCount: Int, interleaved: Bool) throws -> AVAudioFormat {
        let layout = try XCTUnwrap(AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelCount)
        ))
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            interleaved: interleaved,
            channelLayout: layout
        )
    }

    /// Builds an interleaved float32 buffer from per-channel sample arrays.
    private func makeInterleavedBuffer(channels: [[Float]]) throws -> AVAudioPCMBuffer {
        let channelCount = channels.count
        let frameCount = channels[0].count
        let format = try makeFormat(channelCount: channelCount, interleaved: true)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)))
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                samples[frame * channelCount + channel] = channels[channel][frame]
            }
        }
        return buffer
    }

    /// Builds a non-interleaved (one buffer per channel) float32 buffer.
    private func makeNonInterleavedBuffer(channels: [[Float]]) throws -> AVAudioPCMBuffer {
        let channelCount = channels.count
        let frameCount = channels[0].count
        let format = try makeFormat(channelCount: channelCount, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)))
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let data = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<channelCount {
            let dst = data[channel]
            for frame in 0..<frameCount { dst[frame] = channels[channel][frame] }
        }
        return buffer
    }

    private func readInterleaved(_ buffer: AVAudioPCMBuffer) throws -> [[Float]] {
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        return (0..<channelCount).map { channel in
            (0..<frameCount).map { frame in samples[frame * channelCount + channel] }
        }
    }

    private func readNonInterleaved(_ buffer: AVAudioPCMBuffer) throws -> [[Float]] {
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let data = try XCTUnwrap(buffer.floatChannelData)
        return (0..<channelCount).map { channel in
            let src = data[channel]
            return (0..<frameCount).map { frame in src[frame] }
        }
    }

    private func assertChannel(_ actual: [Float], equals expected: [Float], _ message: String = "") {
        XCTAssertEqual(actual.count, expected.count, message)
        for (lhs, rhs) in zip(actual, expected) {
            XCTAssertEqual(lhs, rhs, accuracy: 1e-6, message)
        }
    }

    // MARK: - Interleaved

    func test_interleavedStereo_bothChannelsBecomeMusic_LTCGone() throws {
        let music: [Float] = [0.1, 0.2, -0.3, 0.4]
        let ltc: [Float] = [0.9, -0.9, 0.9, -0.9]
        let buffer = try makeInterleavedBuffer(channels: [music, ltc])

        MusicOnlyMixer.applyInPlace(to: buffer, excludingChannel: 1)

        let out = try readInterleaved(buffer)
        // Single surviving music channel => mean is that channel unchanged, on both.
        assertChannel(out[0], equals: music, "channel 0 must carry the music")
        assertChannel(out[1], equals: music, "channel 1 must carry the music, not the LTC tone")
        // Non-vacuous: the LTC content must appear in neither channel.
        XCTAssertNotEqual(out[1], ltc)
    }

    // MARK: - Non-interleaved

    func test_nonInterleaved3ch_ltcInMiddle_allChannelsAreMeanOfMusic() throws {
        let musicL: [Float] = [0.2, 0.6, -0.4, 1.0]
        let ltc: [Float] = [0.9, -0.9, 0.9, -0.9]
        let musicR: [Float] = [0.4, 0.2, 0.0, -0.2]
        let buffer = try makeNonInterleavedBuffer(channels: [musicL, ltc, musicR])

        MusicOnlyMixer.applyInPlace(to: buffer, excludingChannel: 1)

        let expected = zip(musicL, musicR).map { ($0 + $1) / 2 }
        let out = try readNonInterleaved(buffer)
        assertChannel(out[0], equals: expected)
        assertChannel(out[1], equals: expected, "the former LTC channel must become the music mean")
        assertChannel(out[2], equals: expected)
    }

    // MARK: - Passthrough

    func test_singleChannel_isUnchanged() throws {
        let mono: [Float] = [0.1, -0.2, 0.3, -0.4]
        let buffer = try makeNonInterleavedBuffer(channels: [mono])

        MusicOnlyMixer.applyInPlace(to: buffer, excludingChannel: 0)

        assertChannel(try readNonInterleaved(buffer)[0], equals: mono, "mono buffer must be untouched")
    }

    func test_outOfRangeLTCChannel_isUnchanged() throws {
        let left: [Float] = [0.1, 0.2, 0.3, 0.4]
        let right: [Float] = [-0.1, -0.2, -0.3, -0.4]
        let buffer = try makeInterleavedBuffer(channels: [left, right])

        MusicOnlyMixer.applyInPlace(to: buffer, excludingChannel: 5)

        let out = try readInterleaved(buffer)
        assertChannel(out[0], equals: left, "out-of-range LTC index must be a no-op")
        assertChannel(out[1], equals: right, "out-of-range LTC index must be a no-op")
    }
}
