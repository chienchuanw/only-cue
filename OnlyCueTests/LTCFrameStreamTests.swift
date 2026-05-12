import XCTest
@testable import OnlyCue

final class LTCFrameStreamTests: XCTestCase {

    private func tc(
        _ hours: Int, _ minutes: Int, _ seconds: Int, _ frames: Int, _ rate: SMPTEFramerate = .fps30
    ) -> Timecode {
        guard let timecode = Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate) else {
            preconditionFailure("invalid test timecode")
        }
        return timecode
    }

    func test_samplesPerFrame_matchesRateAndSampleRate() {
        XCTAssertEqual(LTCFrameStream(startTimecode: tc(0, 0, 0, 0, .fps25), sampleRate: 48_000).samplesPerFrame, 1920)
        XCTAssertEqual(LTCFrameStream(startTimecode: tc(0, 0, 0, 0, .fps30), sampleRate: 48_000).samplesPerFrame, 1600)
        XCTAssertEqual(LTCFrameStream(startTimecode: tc(0, 0, 0, 0, .fps24), sampleRate: 48_000).samplesPerFrame, 2000)
        XCTAssertEqual(LTCFrameStream(startTimecode: tc(0, 0, 0, 0, .fps30), sampleRate: 44_100).samplesPerFrame, 1470)
    }

    func test_timecodeAtFrameOffset_advancesAndClamps() {
        let stream = LTCFrameStream(startTimecode: tc(1, 0, 0, 28), sampleRate: 48_000)
        XCTAssertEqual(stream.timecode(atFrameOffset: 0), tc(1, 0, 0, 28))
        XCTAssertEqual(stream.timecode(atFrameOffset: 1), tc(1, 0, 0, 29))
        XCTAssertEqual(stream.timecode(atFrameOffset: 2), tc(1, 0, 1, 0))
        XCTAssertEqual(stream.timecode(atFrameOffset: -5), tc(1, 0, 0, 28))
    }

    func test_samples_emptyForNonPositiveCount() {
        let stream = LTCFrameStream(startTimecode: tc(0, 0, 0, 0), sampleRate: 48_000)
        XCTAssertTrue(stream.samples(frameCount: 0).isEmpty)
        XCTAssertTrue(stream.samples(frameCount: -3).isEmpty)
    }

    func test_samples_lengthIsCountTimesSamplesPerFrame() {
        let stream = LTCFrameStream(startTimecode: tc(0, 0, 0, 0, .fps25), sampleRate: 48_000)
        XCTAssertEqual(stream.samples(frameCount: 1).count, 1920)
        XCTAssertEqual(stream.samples(frameCount: 10).count, 19_200)
    }

    func test_samples_areAtAmplitude() {
        let stream = LTCFrameStream(startTimecode: tc(0, 0, 0, 0), sampleRate: 48_000, amplitude: 0.5)
        for sample in stream.samples(frameCount: 3) {
            XCTAssertEqual(abs(sample), 0.5, accuracy: 1e-6)
        }
    }

    func test_samples_firstFrameMatchesLTCEncoder() {
        let start = tc(2, 13, 4, 7)
        let stream = LTCFrameStream(startTimecode: start, sampleRate: 48_000)
        let direct = LTCEncoder.samples(for: start, sampleRate: 48_000, startLevel: false).samples
        XCTAssertEqual(Array(stream.samples(frameCount: 1)), direct)
    }

    func test_samples_secondFrameStartsFromFirstFramesEndLevel() {
        let start = tc(0, 0, 0, 0, .fps25)
        let stream = LTCFrameStream(startTimecode: start, sampleRate: 48_000)
        let perFrame = stream.samplesPerFrame

        let (frame0, endLevel0) = LTCEncoder.samples(for: start, sampleRate: 48_000, startLevel: false)
        let expectedFrame1 = LTCEncoder.samples(
            for: stream.timecode(atFrameOffset: 1), sampleRate: 48_000, startLevel: endLevel0
        ).samples

        let twoFrames = stream.samples(frameCount: 2)
        XCTAssertEqual(Array(twoFrames.prefix(perFrame)), frame0)
        XCTAssertEqual(Array(twoFrames.suffix(perFrame)), expectedFrame1)
    }

    func test_samples_dropFrameStreamAdvancesAcrossMinuteBoundary() {
        // 00:00:59;29 → next frame is 00:01:00;02 (frames 00/01 skipped).
        let start = tc(0, 0, 59, 29, .fps30drop)
        let stream = LTCFrameStream(startTimecode: start, sampleRate: 48_000)
        XCTAssertEqual(stream.timecode(atFrameOffset: 1), tc(0, 1, 0, 2, .fps30drop))
        XCTAssertEqual(stream.samples(frameCount: 2).count, 2 * stream.samplesPerFrame)
    }
}
