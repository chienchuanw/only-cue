import AVFoundation
import XCTest
@testable import OnlyCue

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
        let url = try Self.makeSilentAsset(duration: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))
        await engine.seek(to: 2.5)

        XCTAssertEqual(engine.currentTime, 2.5, accuracy: 0.05)
    }

    func test_load_populatesDuration() async throws {
        let url = try Self.makeSilentAsset(duration: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: url))

        XCTAssertEqual(engine.duration, 3.0, accuracy: 0.1)
    }

    /// Generates a silent mono PCM WAV file in the temp directory and returns its URL.
    /// Used to give `PlayerEngine` a real asset to seek/load against without bundling
    /// fixture media.
    private static func makeSilentAsset(duration: TimeInterval) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
                channels: 1,
                interleaved: false
            )
        )
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
