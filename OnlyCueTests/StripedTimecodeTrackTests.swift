import XCTest
@testable import OnlyCue

final class StripedTimecodeTrackTests: XCTestCase {

    private func tc(
        _ hours: Int, _ minutes: Int, _ seconds: Int, _ frames: Int, _ rate: SMPTEFramerate = .fps30
    ) -> Timecode {
        guard let timecode = Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate) else {
            preconditionFailure("invalid test timecode")
        }
        return timecode
    }

    func test_initFromFrames_emptyOrZeroRate_isNil() {
        XCTAssertNil(StripedTimecodeTrack(decodedFrames: [], sampleRate: 48_000))
        let frame = LTCDecoder.DecodedFrame(timecode: tc(0, 0, 0, 0), startSample: 0)
        XCTAssertNil(StripedTimecodeTrack(decodedFrames: [frame], sampleRate: 0))
    }

    func test_initFromFrames_anchorsOnFirstFrame() {
        let frames = [
            LTCDecoder.DecodedFrame(timecode: tc(1, 0, 0, 10), startSample: 4_800),  // 0.1 s
            LTCDecoder.DecodedFrame(timecode: tc(1, 0, 0, 11), startSample: 6_400)
        ]
        let track = StripedTimecodeTrack(decodedFrames: frames, sampleRate: 48_000)
        XCTAssertEqual(track?.anchorTimecode, tc(1, 0, 0, 10))
        XCTAssertEqual(track?.anchorPlaybackSeconds ?? -1, 0.1, accuracy: 1e-9)
    }

    func test_timecode_atAnchor_isAnchorTimecode() {
        let track = StripedTimecodeTrack(anchorTimecode: tc(2, 13, 4, 7), anchorPlaybackSeconds: 5.0)
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 5.0), tc(2, 13, 4, 7))
    }

    func test_timecode_extrapolatesForwardAndBackward() {
        // Anchor 01:00:00:00 at 5.0 s, 30 fps.
        let track = StripedTimecodeTrack(anchorTimecode: tc(1, 0, 0, 0), anchorPlaybackSeconds: 5.0)
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 6.0), tc(1, 0, 1, 0))
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 5.5), tc(1, 0, 0, 15))
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 4.0), tc(0, 59, 59, 0))
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 0.0), tc(0, 59, 55, 0))
    }

    func test_timecode_roundsToNearestFrame() {
        let track = StripedTimecodeTrack(anchorTimecode: tc(0, 0, 0, 0), anchorPlaybackSeconds: 0)
        // 0.05 s @ 30 fps = 1.5 frames → rounds to 2.
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 0.05), tc(0, 0, 0, 2))
        // 0.04 s → 1.2 frames → rounds to 1.
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 0.04), tc(0, 0, 0, 1))
    }

    func test_timecode_negativeExtrapolationClampsAtZero() {
        let track = StripedTimecodeTrack(anchorTimecode: tc(0, 0, 0, 2), anchorPlaybackSeconds: 0)
        // 1 s before the anchor is well past 00:00:00:00 — Timecode(frameCount:)
        // clamps negatives, so it stays at the start.
        XCTAssertEqual(track.timecode(atPlaybackSeconds: -1.0), tc(0, 0, 0, 0))
    }

    func test_timecode_dropFrame_skipsAcrossMinuteBoundary() {
        // Anchor 00:00:59;28 (drop-frame) at 0 s. The drop-frame sequence is
        // ;28 → ;29 → 00:01:00;02 → ;03 (frames ;00/;01 skipped at minute 1),
        // so +2 frames (0.0667 s @ 30 fps) is 00:01:00;02 and +3 is 00:01:00;03.
        let track = StripedTimecodeTrack(anchorTimecode: tc(0, 0, 59, 28, .fps30drop), anchorPlaybackSeconds: 0)
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 2.0 / 30.0), tc(0, 1, 0, 2, .fps30drop))
        XCTAssertEqual(track.timecode(atPlaybackSeconds: 0.1), tc(0, 1, 0, 3, .fps30drop))
    }

    func test_roundTrip_fromLTCFrameStreamThroughDecoder() {
        let start = tc(10, 20, 30, 5, .fps25)
        let samples = LTCFrameStream(startTimecode: start, sampleRate: 48_000).samples(frameCount: 8)
        let decoded = LTCDecoder.decode(samples: samples, sampleRate: 48_000)
        let track = StripedTimecodeTrack(decodedFrames: decoded, sampleRate: 48_000)
        XCTAssertNotNil(track)
        // At the anchor's playback second the readout equals the anchor frame.
        XCTAssertEqual(track?.timecode(atPlaybackSeconds: track?.anchorPlaybackSeconds ?? 0), track?.anchorTimecode)
        // 1 s later: anchor + 25 frames.
        let later = track?.timecode(atPlaybackSeconds: (track?.anchorPlaybackSeconds ?? 0) + 1.0)
        XCTAssertEqual(later, track.map { Timecode(frameCount: $0.anchorTimecode.frameCount + 25, rate: .fps25) })
    }
}
