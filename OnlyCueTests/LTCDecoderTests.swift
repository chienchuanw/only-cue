import XCTest
@testable import OnlyCue

final class LTCDecoderTests: XCTestCase {

    private func tc(
        _ hours: Int, _ minutes: Int, _ seconds: Int, _ frames: Int, _ rate: SMPTEFramerate = .fps30
    ) -> Timecode {
        guard let timecode = Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate) else {
            preconditionFailure("invalid test timecode")
        }
        return timecode
    }

    /// Encode a run of frames, decode it back, and check we recover a contiguous
    /// run of timecodes ending at `start + count - 1` (the leading frame or two
    /// can be lost while the demodulator phase-locks).
    private func assertRoundTrips(
        from start: Timecode, count: Int, sampleRate: Double, file: StaticString = #filePath, line: UInt = #line
    ) {
        let samples = LTCFrameStream(startTimecode: start, sampleRate: sampleRate).samples(frameCount: count)
        let decoded = LTCDecoder.decode(samples: samples, sampleRate: sampleRate)
        XCTAssertGreaterThanOrEqual(decoded.count, count - 2, "should recover most frames", file: file, line: line)
        XCTAssertFalse(decoded.isEmpty, file: file, line: line)

        // Whatever it recovered must be a contiguous run of the encoded
        // sequence (the leading and/or trailing frame can be lost while the
        // demodulator phase-locks / when the signal is truncated mid-bit).
        let recovered = decoded.map(\.timecode)
        let expectedFull = (0..<count).map { Timecode(frameCount: start.frameCount + $0, rate: start.rate) }
        guard let firstRecovered = recovered.first, let offset = expectedFull.firstIndex(of: firstRecovered) else {
            XCTFail("first recovered timecode not in the encoded run", file: file, line: line)
            return
        }
        XCTAssertLessThanOrEqual(offset, 1, "should lose at most the leading frame", file: file, line: line)
        XCTAssertEqual(recovered, Array(expectedFull[offset..<(offset + recovered.count)]), file: file, line: line)
        XCTAssertGreaterThanOrEqual(offset + recovered.count, count - 1, "should lose at most the trailing frame", file: file, line: line)
        // And the rate (incl. drop-frame) round-trips.
        XCTAssertEqual(decoded.first?.timecode.rate, start.rate, file: file, line: line)
    }

    func test_roundTrip_30fps_48k() {
        assertRoundTrips(from: tc(1, 23, 45, 12), count: 6, sampleRate: 48_000)
    }

    func test_roundTrip_25fps_48k() {
        assertRoundTrips(from: tc(0, 0, 0, 0, .fps25), count: 6, sampleRate: 48_000)
    }

    func test_roundTrip_24fps_48k() {
        assertRoundTrips(from: tc(10, 30, 0, 5, .fps24), count: 6, sampleRate: 48_000)
    }

    func test_roundTrip_dropFrame_recoversDropFrameRate() {
        // Spans a minute boundary: 00:00:59;28 → ;29 → 00:01:00;02 → ;03 ...
        assertRoundTrips(from: tc(0, 0, 59, 28, .fps30drop), count: 6, sampleRate: 48_000)
    }

    func test_roundTrip_44100() {
        assertRoundTrips(from: tc(2, 0, 0, 0), count: 6, sampleRate: 44_100)
    }

    func test_startSample_isMonotonicAndFrameSpaced() {
        let start = tc(0, 0, 10, 0, .fps25)
        let sampleRate = 48_000.0
        let stream = LTCFrameStream(startTimecode: start, sampleRate: sampleRate)
        let decoded = LTCDecoder.decode(samples: stream.samples(frameCount: 5), sampleRate: sampleRate)
        XCTAssertGreaterThanOrEqual(decoded.count, 2)
        for index in 1..<decoded.count {
            let delta = decoded[index].startSample - decoded[index - 1].startSample
            // One frame apart, within a few samples of slack for crossing jitter.
            XCTAssertEqual(Double(delta), Double(stream.samplesPerFrame), accuracy: 3)
        }
    }

    func test_decode_silence_yieldsNothing() {
        XCTAssertTrue(LTCDecoder.decode(samples: [Float](repeating: 0, count: 4_800), sampleRate: 48_000).isEmpty)
    }

    func test_decode_tooShort_yieldsNothing() {
        XCTAssertTrue(LTCDecoder.decode(samples: [0.5, -0.5, 0.5], sampleRate: 48_000).isEmpty)
    }

    func test_decode_noise_doesNotCrashAndYieldsNoValidFrames() {
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<48_000).map { _ in Float.random(in: -1...1, using: &generator) }
        // Random sign flips will never align into 80-bit sync-word-terminated frames.
        XCTAssertTrue(LTCDecoder.decode(samples: noise, sampleRate: 48_000).isEmpty)
    }

    func test_frame_bitsRoundTripThroughRawInit() {
        let original = LTCFrame(timecode: tc(7, 8, 9, 10))
        let rewrapped = LTCFrame(bits: original.bits)
        XCTAssertEqual(rewrapped, original)
        XCTAssertTrue(rewrapped.isWellFormed)
        XCTAssertEqual(rewrapped.timecode(framesPerSecond: 30), tc(7, 8, 9, 10))
    }

    func test_frame_timecode_nilForUnsupportedRate() {
        let frame = LTCFrame(timecode: tc(0, 0, 0, 0))
        XCTAssertNil(frame.timecode(framesPerSecond: 60))
        XCTAssertNil(frame.timecode(framesPerSecond: 23))
    }

    func test_smpteFramerate_matching() {
        XCTAssertEqual(SMPTEFramerate.matching(framesPerSecond: 24, isDropFrame: false), .fps24)
        XCTAssertEqual(SMPTEFramerate.matching(framesPerSecond: 25, isDropFrame: false), .fps25)
        XCTAssertEqual(SMPTEFramerate.matching(framesPerSecond: 30, isDropFrame: false), .fps30)
        XCTAssertEqual(SMPTEFramerate.matching(framesPerSecond: 30, isDropFrame: true), .fps30drop)
        XCTAssertNil(SMPTEFramerate.matching(framesPerSecond: 25, isDropFrame: true))
        XCTAssertNil(SMPTEFramerate.matching(framesPerSecond: 60, isDropFrame: false))
    }

    // MARK: - Silent lead-in (#793)

    /// Mimics the dither mp3 decoding leaves in "digital silence": amplitude
    /// 2e-5 with the sign flipping every sample. The real file measured a
    /// 2.35e-5 peak with 95998 of 96000 samples non-zero; alternating signs
    /// is that case at its worst, and is deterministic.
    private func silenceDither(seconds: Double, sampleRate: Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { $0 % 2 == 0 ? Float(2e-5) : Float(-2e-5) }
    }

    func test_decode_ltcPrecededBySilentLeadIn_stillDecodes() {
        let sampleRate = 48_000.0
        let start = tc(8, 0, 0, 18, .fps30)
        let stream = LTCFrameStream(startTimecode: start, sampleRate: sampleRate)
        let samples = silenceDither(seconds: 2.0, sampleRate: sampleRate)
            + stream.samples(frameCount: 30)

        let frames = LTCDecoder.decode(samples: samples, sampleRate: sampleRate)

        XCTAssertGreaterThanOrEqual(frames.count, 28, "expected ~30 frames, got \(frames.count)")
        XCTAssertEqual(frames.first?.timecode.rate, .fps30)
        // The demodulator can lose the leading frame while it phase-locks — the
        // same tolerance `assertRoundTrips` above allows on a clean signal.
        let firstOffset = (frames.first?.timecode.frameCount ?? -1) - start.frameCount
        XCTAssertTrue(
            (0...1).contains(firstOffset),
            "first frame should be the start or the one after it, got offset \(firstOffset)"
        )
        XCTAssertGreaterThanOrEqual(
            frames.first?.startSample ?? 0,
            96_000 - 100,
            "the first frame must sit after the 2 s lead-in, not inside it"
        )
    }

    func test_decode_pureSilenceDither_findsNothing() {
        // Pins the global-reference constraint: a buffer that is *only* noise
        // must be rejected by the RMS floor, not normalised up to it.
        let samples = silenceDither(seconds: 2.0, sampleRate: 48_000.0)
        XCTAssertTrue(LTCDecoder.decode(samples: samples, sampleRate: 48_000.0).isEmpty)
    }

    func test_decode_loudNonLTCTone_findsNoFrames() {
        // The more permissive front end must not invent frames in music.
        let sampleRate = 48_000.0
        let samples = (0..<Int(sampleRate * 2)).map { index in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
        }
        XCTAssertTrue(LTCDecoder.decode(samples: samples, sampleRate: sampleRate).isEmpty)
    }
}
