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

    func test_load_populatesDuration() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))

        XCTAssertEqual(engine.duration, 3.0, accuracy: 0.1)
    }
}
