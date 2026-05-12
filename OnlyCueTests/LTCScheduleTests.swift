import XCTest
@testable import OnlyCue

final class LTCScheduleTests: XCTestCase {

    private func tc(
        _ hours: Int, _ minutes: Int, _ seconds: Int, _ frames: Int, _ rate: SMPTEFramerate = .fps30
    ) -> Timecode {
        guard let timecode = Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate) else {
            preconditionFailure("invalid test timecode")
        }
        return timecode
    }

    func test_timecodeForBufferIndex_advancesByFramesPerBuffer() {
        let schedule = LTCSchedule(startTimecode: tc(1, 0, 0, 0), sampleRate: 48_000, framesPerBuffer: 3)
        XCTAssertEqual(schedule.timecode(forBufferIndex: 0), tc(1, 0, 0, 0))
        XCTAssertEqual(schedule.timecode(forBufferIndex: 1), tc(1, 0, 0, 3))
        XCTAssertEqual(schedule.timecode(forBufferIndex: 10), tc(1, 0, 1, 0))
        XCTAssertEqual(schedule.timecode(forBufferIndex: -2), tc(1, 0, 0, 0))
    }

    func test_timecode_dropFrame_crossesMinuteBoundary() {
        // framesPerBuffer 2, starting at 00:00:59;28: buffer 0 = ;28, buffer 1 = 00:01:00;02
        let schedule = LTCSchedule(startTimecode: tc(0, 0, 59, 28, .fps30drop), sampleRate: 48_000, framesPerBuffer: 2)
        XCTAssertEqual(schedule.timecode(forBufferIndex: 0), tc(0, 0, 59, 28, .fps30drop))
        XCTAssertEqual(schedule.timecode(forBufferIndex: 1), tc(0, 1, 0, 2, .fps30drop))
    }

    func test_samplesPerBuffer_andSamples_matchLTCFrameStream() {
        let start = tc(2, 13, 4, 7, .fps25)
        let schedule = LTCSchedule(startTimecode: start, sampleRate: 48_000, framesPerBuffer: 4)
        XCTAssertEqual(schedule.samplesPerBuffer, 4 * 1920)
        let expected = LTCFrameStream(startTimecode: start, sampleRate: 48_000).samples(frameCount: 4)
        XCTAssertEqual(schedule.samples(forBufferIndex: 0), expected)
        XCTAssertEqual(schedule.samples(forBufferIndex: 0).count, schedule.samplesPerBuffer)
    }

    func test_samples_secondBufferStartsAtNextTimecodeRun() {
        let start = tc(0, 0, 0, 0)
        let framesPerBuffer = 5
        let schedule = LTCSchedule(startTimecode: start, sampleRate: 48_000, framesPerBuffer: framesPerBuffer)
        let bufferOne = schedule.samples(forBufferIndex: 1)
        let expected = LTCFrameStream(
            startTimecode: Timecode(frameCount: start.frameCount + framesPerBuffer, rate: start.rate),
            sampleRate: 48_000
        ).samples(frameCount: framesPerBuffer)
        XCTAssertEqual(bufferOne, expected)
    }

    func test_nextBuffer_isSequentialAndAdvancesEmittedCount() {
        var schedule = LTCSchedule(startTimecode: tc(0, 0, 10, 0), sampleRate: 48_000, framesPerBuffer: 2)
        XCTAssertEqual(schedule.emittedBuffers, 0)
        let first = schedule.nextBuffer()
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.timecode, tc(0, 0, 10, 0))
        XCTAssertEqual(first.samples, schedule.samples(forBufferIndex: 0))
        let second = schedule.nextBuffer()
        XCTAssertEqual(second.index, 1)
        XCTAssertEqual(second.timecode, tc(0, 0, 10, 2))
        XCTAssertEqual(schedule.emittedBuffers, 2)
    }

    func test_bufferDuration() {
        let fiveAt25 = LTCSchedule(startTimecode: tc(0, 0, 0, 0, .fps25), sampleRate: 48_000, framesPerBuffer: 5)
        let threeAt30 = LTCSchedule(startTimecode: tc(0, 0, 0, 0), sampleRate: 48_000, framesPerBuffer: 3)
        XCTAssertEqual(fiveAt25.bufferDuration, 0.2, accuracy: 1e-9)
        XCTAssertEqual(threeAt30.bufferDuration, 0.1, accuracy: 1e-9)
    }

    func test_targetBufferCount() {
        // 3 frames @ 30 fps = 0.1 s/buffer.
        let schedule = LTCSchedule(startTimecode: tc(0, 0, 0, 0), sampleRate: 48_000, framesPerBuffer: 3)
        XCTAssertEqual(schedule.targetBufferCount(elapsedSeconds: 0, leadBuffers: 2), 2)
        XCTAssertEqual(schedule.targetBufferCount(elapsedSeconds: 0.25, leadBuffers: 2), 3 + 2)
        XCTAssertEqual(schedule.targetBufferCount(elapsedSeconds: 0.3, leadBuffers: 0), 3)
        XCTAssertEqual(schedule.targetBufferCount(elapsedSeconds: -1, leadBuffers: 4), 4)
    }

    func test_framesPerBufferForTargetSeconds() {
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: 0.1, rate: .fps30), 3)
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: 0.1, rate: .fps25), 3)   // 2.5 → 3
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: 0.1, rate: .fps24), 2)   // 2.4 → 2
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: 0, rate: .fps30), 1)
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: -5, rate: .fps30), 1)
    }
}
