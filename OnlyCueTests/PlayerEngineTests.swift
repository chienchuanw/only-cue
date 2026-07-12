import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class PlayerEngineTests: XCTestCase {

    func test_play_setsRateToOne() {
        let engine = PlayerEngine()
        engine.play()
        XCTAssertEqual(engine.rate, 1.0, accuracy: 0.001)
    }

    func test_play_reAnchorsObservedAt_forSmoothResume() async throws {
        // #537: on resume, play() must re-anchor currentTimeObservedAt to "now".
        // Otherwise PlayheadInterpolator extrapolates currentTime forward by the
        // whole paused gap (rate * (now - staleObservedAt)) until the next
        // observer tick, producing a visible jump-then-snap-back.
        let engine = PlayerEngine()
        // Let the anchor (set at construction) age, simulating a paused gap.
        try await Task.sleep(for: .milliseconds(60))
        let resumeInstant = CACurrentMediaTime()
        engine.play()
        XCTAssertGreaterThanOrEqual(
            engine.currentTimeObservedAt,
            resumeInstant - 0.005,
            "play() must re-anchor the time observation to ~now, not leave it stale"
        )
    }

    func test_pause_resetsRateToZero() {
        let engine = PlayerEngine()
        engine.play()
        engine.pause()
        XCTAssertEqual(engine.rate, 0.0, accuracy: 0.001)
    }

    func test_seek_updatesCurrentTime() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))
        await engine.seek(to: 2.5)

        XCTAssertEqual(engine.currentTime, 2.5, accuracy: 0.05)
    }

    // MARK: - Output-latency compensation (#611)

    /// play() must refresh `outputLatency` from the injected provider so the
    /// rendered playhead can subtract the audio pipeline's in-flight delay.
    /// Queried at play-time (not init) because the user can switch output
    /// devices between sessions of playback.
    func test_play_refreshesOutputLatencyFromProvider() {
        let engine = PlayerEngine(outputLatencyProvider: { 0.123 })
        XCTAssertEqual(engine.outputLatency, 0, accuracy: 1e-9, "no latency before first play")
        engine.play()
        XCTAssertEqual(engine.outputLatency, 0.123, accuracy: 1e-9)
    }

    func test_defaultProvider_yieldsSaneLatency() {
        // Default wiring goes to AudioOutputLatency.currentSeconds(), which
        // clamps to [0, 0.5] — the engine must inherit that sanity range.
        let engine = PlayerEngine()
        engine.play()
        XCTAssertGreaterThanOrEqual(engine.outputLatency, 0)
        XCTAssertLessThanOrEqual(engine.outputLatency, 0.5)
    }

    func test_load_populatesDuration() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))

        XCTAssertEqual(engine.duration, 3.0, accuracy: 0.1)
    }
}
