import AVFoundation
import XCTest
@testable import OnlyCue

/// Coverage for `LTCEncoder` — turning a `Timecode` into LTC `Float` PCM at a
/// given sample rate (epic #33; finishes the encoder side ahead of the routing
/// leaf).
final class LTCEncoderTests: XCTestCase {

    private func tc(_ hour: Int, _ minute: Int, _ second: Int, _ frame: Int, _ rate: SMPTEFramerate = .fps30) throws -> Timecode {
        try XCTUnwrap(Timecode(hours: hour, minutes: minute, seconds: second, frames: frame, rate: rate))
    }

    func test_sampleCount_at48kHz_isSampleRateOverFps() throws {
        XCTAssertEqual(LTCEncoder.samples(for: try tc(0, 0, 0, 0, .fps25), sampleRate: 48_000).samples.count, 1920)
        XCTAssertEqual(LTCEncoder.samples(for: try tc(0, 0, 0, 0, .fps30), sampleRate: 48_000).samples.count, 1600)
        XCTAssertEqual(LTCEncoder.samples(for: try tc(0, 0, 0, 0, .fps30drop), sampleRate: 48_000).samples.count, 1600)
        XCTAssertEqual(LTCEncoder.samples(for: try tc(0, 0, 0, 0, .fps24), sampleRate: 48_000).samples.count, 2000)
    }

    func test_sampleCount_at44_1kHz_matchesRoundedFrameLength() throws {
        // 44100 / 25 = 1764 exactly; the rounded half-bit slot boundaries must sum to it.
        XCTAssertEqual(LTCEncoder.samples(for: try tc(1, 2, 3, 4, .fps25), sampleRate: 44_100).samples.count, 1764)
        // 44100 / 30 = 1470 exactly.
        XCTAssertEqual(LTCEncoder.samples(for: try tc(1, 2, 3, 4, .fps30), sampleRate: 44_100).samples.count, 1470)
    }

    func test_everySample_isPlusOrMinusAmplitude() throws {
        let (samples, _) = LTCEncoder.samples(for: try tc(12, 34, 56, 23, .fps30), sampleRate: 48_000, amplitude: 0.5)
        XCTAssertTrue(samples.allSatisfy { $0 == 0.5 || $0 == -0.5 })
        XCTAssertFalse(samples.isEmpty)
    }

    func test_firstSample_reflectsOpeningBoundaryTransition() throws {
        // startLevel false → the first bit's boundary transition flips it high → first sample is +amplitude.
        let low = LTCEncoder.samples(for: try tc(0, 0, 0, 0, .fps30), sampleRate: 48_000, startLevel: false).samples
        XCTAssertEqual(low.first, LTCEncoder.defaultAmplitude)
        let high = LTCEncoder.samples(for: try tc(0, 0, 0, 0, .fps30), sampleRate: 48_000, startLevel: true).samples
        XCTAssertEqual(high.first, -LTCEncoder.defaultAmplitude)
    }

    func test_endLevel_chainsAcrossFrames() throws {
        let first = LTCEncoder.samples(for: try tc(0, 0, 0, 0, .fps30), sampleRate: 48_000, startLevel: false)
        let second = LTCEncoder.samples(for: try tc(0, 0, 0, 1, .fps30), sampleRate: 48_000, startLevel: first.endLevel)
        // The next frame's first sample is the level *after* the opening boundary toggle = !startLevel = !first.endLevel.
        let expectedFirst: Float = first.endLevel ? -LTCEncoder.defaultAmplitude : LTCEncoder.defaultAmplitude
        XCTAssertEqual(second.samples.first, expectedFirst)
    }

    func test_atOneSamplePerHalfBit_signSequenceMatchesBiphaseLevels() throws {
        // sampleRate = 160 · fps → exactly one sample per half-bit slot → 160 samples,
        // and their signs are the raw biphase-mark level sequence.
        let timecode = try tc(10, 20, 30, 15, .fps30)
        let (samples, _) = LTCEncoder.samples(for: timecode, sampleRate: 160.0 * 30.0, startLevel: false)
        XCTAssertEqual(samples.count, 160)
        let frame = LTCFrame(timecode: timecode)
        let (levels, _) = LTCBiphaseEncoder.levels(for: frame.bits, samplesPerHalfBit: 1, startLevel: false)
        XCTAssertEqual(samples.map { $0 > 0 }, levels)
    }

    func test_makeBuffer_hasCorrectFormatAndLength() throws {
        let buffer = try XCTUnwrap(LTCEncoder.makeBuffer(for: try tc(1, 0, 0, 0, .fps25), sampleRate: 48_000))
        XCTAssertEqual(buffer.format.sampleRate, 48_000)
        XCTAssertEqual(buffer.format.channelCount, 1)
        XCTAssertEqual(Int(buffer.frameLength), 1920)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(channel.pointee[0], LTCEncoder.defaultAmplitude)   // opening boundary transition
    }
}
