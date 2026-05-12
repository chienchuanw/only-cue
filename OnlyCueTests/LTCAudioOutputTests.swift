import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class LTCAudioOutputTests: XCTestCase {

    private func format(channels: Int, sampleRate: Double = 48_000) throws -> AVAudioFormat {
        try XCTUnwrap(LTCAudioOutput.renderFormat(channelCount: channels, sampleRate: sampleRate))
    }

    func test_renderFormat_supportsNonStandardChannelCounts() throws {
        XCTAssertEqual(try format(channels: 4).channelCount, 4)
        XCTAssertEqual(try format(channels: 1).channelCount, 1)
        XCTAssertEqual(try format(channels: 8).channelCount, 8)
        XCTAssertNil(LTCAudioOutput.renderFormat(channelCount: 0, sampleRate: 48_000))
    }

    func test_makeBuffer_placesSamplesOnTargetChannelAndSilencesOthers() throws {
        let mono: [Float] = [0.1, -0.2, 0.3, -0.4]
        let buffer = try XCTUnwrap(LTCAudioOutput.makeBuffer(monoSamples: mono, format: try format(channels: 4), channel: 2))
        XCTAssertEqual(Int(buffer.frameLength), mono.count)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<4 {
            let values = Array(UnsafeBufferPointer(start: channels[index], count: mono.count))
            XCTAssertEqual(values, index == 2 ? mono : [Float](repeating: 0, count: mono.count), "channel \(index)")
        }
    }

    func test_makeBuffer_clampsOutOfRangeChannel() throws {
        let mono: [Float] = [1, 2, 3]
        let buffer = try XCTUnwrap(LTCAudioOutput.makeBuffer(monoSamples: mono, format: try format(channels: 2), channel: 9))
        let channels = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: channels[1], count: mono.count)), mono)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: channels[0], count: mono.count)), [0, 0, 0])
    }

    func test_makeBuffer_monoFormat_putsSamplesOnTheOnlyChannel() throws {
        let mono: [Float] = [0.5, -0.5]
        let buffer = try XCTUnwrap(LTCAudioOutput.makeBuffer(monoSamples: mono, format: try format(channels: 1), channel: 0))
        let channels = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: channels[0], count: mono.count)), mono)
    }

    func test_makeBuffer_emptyInput_isNil() throws {
        XCTAssertNil(LTCAudioOutput.makeBuffer(monoSamples: [], format: try format(channels: 2), channel: 0))
    }

    func test_makeBufferMulti_placesEachSourceOnItsChannel() throws {
        let left: [Float] = [0.1, 0.2, 0.3, 0.4]
        let right: [Float] = [-0.1, -0.2, -0.3, -0.4]
        let buffer = try XCTUnwrap(LTCAudioOutput.makeBuffer(
            channels: [(samples: left, channel: 1), (samples: right, channel: 2)],
            format: try format(channels: 4)))
        XCTAssertEqual(Int(buffer.frameLength), 4)
        let data = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data[0], count: 4)), [Float](repeating: 0, count: 4))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data[1], count: 4)), left)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data[2], count: 4)), right)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data[3], count: 4)), [Float](repeating: 0, count: 4))
    }

    func test_makeBufferMulti_clampsOutOfRangeChannel() throws {
        let mono: [Float] = [1, 2]
        let buffer = try XCTUnwrap(LTCAudioOutput.makeBuffer(
            channels: [(samples: mono, channel: 9)], format: try format(channels: 2)))
        let data = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data[1], count: 2)), mono)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data[0], count: 2)), [0, 0])
    }

    func test_makeBufferMulti_mismatchedLengths_isNil() throws {
        XCTAssertNil(LTCAudioOutput.makeBuffer(
            channels: [(samples: [1, 2, 3], channel: 0), (samples: [1, 2], channel: 1)],
            format: try format(channels: 2)))
    }

    func test_makeBufferMulti_emptyOrZeroLength_isNil() throws {
        XCTAssertNil(LTCAudioOutput.makeBuffer(channels: [], format: try format(channels: 2)))
        XCTAssertNil(LTCAudioOutput.makeBuffer(channels: [(samples: [], channel: 0)], format: try format(channels: 2)))
    }

    func test_buffersToSchedule_fillsTheGapToTarget() {
        XCTAssertEqual(LTCAudioOutput.buffersToSchedule(outstanding: 0, target: 5), 5)
        XCTAssertEqual(LTCAudioOutput.buffersToSchedule(outstanding: 3, target: 5), 2)
        XCTAssertEqual(LTCAudioOutput.buffersToSchedule(outstanding: 5, target: 5), 0)
    }

    func test_buffersToSchedule_neverNegative_evenIfOverfilledOrNegativeInput() {
        XCTAssertEqual(LTCAudioOutput.buffersToSchedule(outstanding: 9, target: 5), 0)
        XCTAssertEqual(LTCAudioOutput.buffersToSchedule(outstanding: -2, target: 5), 5)
    }

    func test_freshInstance_isNotRunning() {
        let output = LTCAudioOutput()
        XCTAssertFalse(output.isRunning)
        XCTAssertNil(output.lastError)
    }

    func test_stop_whenNotRunning_isHarmless() {
        let output = LTCAudioOutput()
        output.stop()
        XCTAssertFalse(output.isRunning)
    }

    func test_update_whenNotRunning_isHarmless() {
        let output = LTCAudioOutput()
        guard let timecode = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps30) else {
            return XCTFail("invalid timecode")
        }
        output.update(at: timecode)
        XCTAssertFalse(output.isRunning)
    }

    func test_start_withNoLTCChannel_recordsErrorAndStaysStopped() {
        let output = LTCAudioOutput()
        let routing = LTCRoutingSettings(deviceUID: nil, channelRoles: [.trackLeft, .trackRight])
        guard let timecode = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, rate: .fps30) else {
            return XCTFail("invalid timecode")
        }
        output.start(at: timecode, routing: routing)
        XCTAssertFalse(output.isRunning)
        XCTAssertNotNil(output.lastError)
    }
}
