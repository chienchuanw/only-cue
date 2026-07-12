import XCTest
@testable import OnlyCue

final class AudioOutputLatencyTests: XCTestCase {

    // MARK: - Pure frame→seconds math

    func test_seconds_sumsAllLatencyContributionsOverSampleRate() {
        // device 128 + safety 144 + buffer 512 + stream 160 = 944 frames @ 48k
        let result = AudioOutputLatency.seconds(
            deviceLatencyFrames: 128,
            safetyOffsetFrames: 144,
            bufferFrames: 512,
            streamLatencyFrames: 160,
            sampleRate: 48_000
        )
        XCTAssertEqual(result, 944.0 / 48_000.0, accuracy: 1e-9)
    }

    func test_seconds_zeroSampleRate_returnsZero() {
        let result = AudioOutputLatency.seconds(
            deviceLatencyFrames: 128,
            safetyOffsetFrames: 144,
            bufferFrames: 512,
            streamLatencyFrames: 160,
            sampleRate: 0
        )
        XCTAssertEqual(result, 0)
    }

    // MARK: - Live device query

    /// Whatever the default output device reports, the compensation must stay
    /// sane: never negative, and under a second (a garbage value here would
    /// visibly yank the playhead).
    func test_currentSeconds_isWithinSaneBounds() {
        let latency = AudioOutputLatency.currentSeconds()
        XCTAssertGreaterThanOrEqual(latency, 0)
        XCTAssertLessThan(latency, 1.0)
    }
}
