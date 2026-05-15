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

    func test_play_appliesCustomPlaybackRate() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))
        engine.setPlaybackRate(0.5)
        engine.play()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(engine.player.rate, 0.5, accuracy: 0.01)
        engine.pause()
    }

    func test_setPlaybackRate_whilePlaying_updatesAVPlayerRateLive() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))
        engine.play()
        try await Task.sleep(nanoseconds: 80_000_000)

        engine.setPlaybackRate(1.5)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(engine.player.rate, 1.5, accuracy: 0.01)

        engine.setPlaybackRate(0.5)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(engine.player.rate, 0.5, accuracy: 0.01)

        engine.pause()
    }

    func test_controller_rateChangeRejectedWhileLTCActive() {
        let engine = PlayerEngine()
        var blockedSignals = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .playbackRateInterlockBlocked,
            object: nil,
            queue: .main
        ) { _ in blockedSignals += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Allowed: target rate == 1.0× while LTC active is fine.
        PlaybackRateController.apply(.reset, engine: engine, ltcEnabled: true)
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(blockedSignals, 0)

        // Blocked: any non-1.0× target while LTC active is a no-op + signal.
        PlaybackRateController.apply(.up, engine: engine, ltcEnabled: true)
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(blockedSignals, 1)

        PlaybackRateController.apply(.down, engine: engine, ltcEnabled: true)
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(blockedSignals, 2)
    }

    func test_controller_appliesChangeWhenLTCInactive() {
        let engine = PlayerEngine()

        PlaybackRateController.apply(.up, engine: engine, ltcEnabled: false)
        XCTAssertEqual(engine.playbackRate, 1.1, accuracy: 0.0001)

        PlaybackRateController.apply(.down, engine: engine, ltcEnabled: false)
        PlaybackRateController.apply(.down, engine: engine, ltcEnabled: false)
        XCTAssertEqual(engine.playbackRate, 0.9, accuracy: 0.0001)

        PlaybackRateController.apply(.reset, engine: engine, ltcEnabled: false)
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
    }

    func test_load_setsPitchPreservingTimeStretch() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))

        // We request `.spectral`, but AVFoundation may downgrade to
        // `.timeDomain` depending on the asset / host. Both preserve pitch.
        // The contract this test enforces: we never end up on `.varispeed`
        // (which would chipmunk the audio at rate != 1.0×).
        let algorithm = engine.player.currentItem?.audioTimePitchAlgorithm
        XCTAssertNotEqual(algorithm, .varispeed)
        XCTAssertTrue(
            algorithm == .spectral || algorithm == .timeDomain,
            "Expected a pitch-preserving time-stretch algorithm; got \(String(describing: algorithm))"
        )
    }
}
