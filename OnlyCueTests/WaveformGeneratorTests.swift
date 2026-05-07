import AVFoundation
import XCTest
@testable import OnlyCue

final class WaveformGeneratorTests: XCTestCase {

    func test_peaks_returnsRequestedResolution() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 64)

        XCTAssertEqual(peaks.count, 64)
    }

    func test_peaks_silentInput_isAllZero() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 32)

        XCTAssertEqual(peaks.max() ?? 1, 0, accuracy: 0.001)
    }

    func test_peaks_sineInput_isNonZero() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 64)

        XCTAssertGreaterThan(peaks.max() ?? 0, 0.5)
        XCTAssertLessThanOrEqual(peaks.max() ?? 1, 1.0)
    }

    func test_peaks_assetWithNoAudioTrack_returnsFlatPeaks() async throws {
        let composition = AVMutableComposition()

        let peaks = try await WaveformGenerator.peaks(for: composition, resolution: 48)

        XCTAssertEqual(peaks.count, 48)
        XCTAssertEqual(peaks.max() ?? 1, 0, accuracy: 0.001)
    }

    func test_peaks_normalizedTo01() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 32)

        for peak in peaks {
            XCTAssertGreaterThanOrEqual(peak, 0)
            XCTAssertLessThanOrEqual(peak, 1)
        }
    }
}
