import AVFoundation
import XCTest
@testable import OnlyCue

final class VideoPosterGeneratorTests: XCTestCase {

    func test_captureTime_isTenPercentOfDuration() {
        let time = VideoPosterGenerator.captureTime(forDurationSeconds: 100)
        XCTAssertEqual(CMTimeGetSeconds(time), 10, accuracy: 0.001)
    }

    func test_captureTime_negativeDuration_clampsToZero() {
        let time = VideoPosterGenerator.captureTime(forDurationSeconds: -5)
        XCTAssertEqual(CMTimeGetSeconds(time), 0, accuracy: 0.001)
    }

    func test_captureTime_subSecondClip_isNonNegative() {
        let time = VideoPosterGenerator.captureTime(forDurationSeconds: 0.5)
        XCTAssertGreaterThanOrEqual(CMTimeGetSeconds(time), 0)
        XCTAssertEqual(CMTimeGetSeconds(time), 0.05, accuracy: 0.001)
    }

    func test_poster_solidRedClip_returnsImageWithPositiveDimensions() async throws {
        let url = try await VideoFixture.makeMOV(duration: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try await VideoPosterGenerator.poster(for: AVURLAsset(url: url))

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func test_poster_assetWithNoVideoTrack_throwsGenerationFailed() async {
        let composition = AVMutableComposition()
        do {
            _ = try await VideoPosterGenerator.poster(for: composition)
            XCTFail("Expected VideoPosterError.generationFailed")
        } catch {
            XCTAssertEqual(error as? VideoPosterError, .generationFailed)
        }
    }
}
