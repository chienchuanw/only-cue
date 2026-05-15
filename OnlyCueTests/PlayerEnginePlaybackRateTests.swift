import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class PlayerEnginePlaybackRateTests: XCTestCase {

    func test_defaultPlaybackRate_isOnePointZero() {
        let engine = PlayerEngine()
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
    }

    func test_setPlaybackRate_clampsAndSnaps() {
        let engine = PlayerEngine()

        engine.setPlaybackRate(-1.0)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.0)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.04)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.14)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.15)
        XCTAssertEqual(engine.playbackRate, 0.2, accuracy: 0.0001)

        engine.setPlaybackRate(2.46)
        XCTAssertEqual(engine.playbackRate, 2.5, accuracy: 0.0001)

        engine.setPlaybackRate(3.05)
        XCTAssertEqual(engine.playbackRate, 3.0, accuracy: 0.0001)

        engine.setPlaybackRate(99.0)
        XCTAssertEqual(engine.playbackRate, 3.0, accuracy: 0.0001)
    }

    func test_nudgePlaybackRate_up_stopsAtThree() {
        let engine = PlayerEngine()
        for _ in 0..<25 {
            engine.nudgePlaybackRate(by: 0.1)
        }
        XCTAssertEqual(engine.playbackRate, 3.0, accuracy: 0.0001)
    }

    func test_nudgePlaybackRate_down_stopsAtOneTenth() {
        let engine = PlayerEngine()
        for _ in 0..<25 {
            engine.nudgePlaybackRate(by: -0.1)
        }
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)
    }

    func test_resetPlaybackRate_returnsToOne() {
        let engine = PlayerEngine()
        engine.setPlaybackRate(0.5)
        engine.resetPlaybackRate()
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
    }
}
