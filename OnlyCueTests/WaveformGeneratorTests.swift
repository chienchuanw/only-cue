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

    func test_peaks_quietInput_isNormalizedToOwnMax() async throws {
        // #538: a quiet file must be normalized to its own maximum so its shape
        // is visible, instead of rendering as a tiny flat envelope (and, by the
        // same token, loud files no longer saturate to a solid block).
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440, amplitude: 0.2)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 64)

        XCTAssertEqual(peaks.max() ?? 0, 1.0, accuracy: 0.02)
    }

    // MARK: - RMS energy rendering (#632)

    /// Two regions with the SAME peak (full scale) but different energy: the
    /// first is a continuous full-scale square (RMS 1.0); the second fires a
    /// full-scale sample only every 4th frame (peak 1.0, RMS 0.5). A peak
    /// envelope renders both regions at the same height; an RMS envelope renders
    /// the low-energy region at roughly half height. This is the guard for the
    /// "loud master looks like a solid block" report.
    func test_peaks_equalPeakDifferentEnergy_rendersByRMSNotPeak() async throws {
        let url = try SilentAudioFixture.makeCustomWAV(duration: 4) { frame, sr in
            let firstHalf = Double(frame) < sr * 2
            if firstHalf {
                return frame % 2 == 0 ? 1.0 : -1.0     // full-scale square → RMS 1.0
            } else {
                return frame % 4 == 0 ? 1.0 : 0.0       // sparse full-scale → peak 1.0, RMS 0.5
            }
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 4)

        // Buckets 0-1 cover the loud region, 2-3 the low-energy region.
        let loud = (peaks[0] + peaks[1]) / 2
        let quiet = (peaks[2] + peaks[3]) / 2
        XCTAssertEqual(loud, 1.0, accuracy: 0.05, "loud region normalizes to full height")
        XCTAssertEqual(quiet, 0.5, accuracy: 0.1, "equal-peak but half-energy region must render at ~half height (RMS, not peak)")
        XCTAssertLessThan(quiet, loud * 0.75, "peak rendering would make these equal — RMS must separate them")
    }

    // MARK: - Click placement instrumentation (#611)

    /// A click at exactly 10.000s in a 20s file must land in the bucket
    /// covering 10.000s — bucket 100 of 200 (±1 for bucket-edge rounding).
    /// This is the deterministic ruler for the reported audio↔visual offset.
    func test_peaks_clickAt10s_landsInCorrectBucket() async throws {
        let url = try SilentAudioFixture.makeClickWAV(duration: 20, clickAt: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 200)

        let argmax = try XCTUnwrap(peaks.indices.max(by: { peaks[$0] < peaks[$1] }))
        XCTAssertEqual(argmax, 100, accuracy: 1, "click at 10.000s of 20s must land at bucket ~100/200")
    }

    /// Same ruler through the 48 kHz → 44.1 kHz resample path: a sample-rate
    /// conversion bug would shift or stretch the click's bucket position.
    func test_peaks_clickAt10s_48kSource_landsInCorrectBucket() async throws {
        let url = try SilentAudioFixture.makeClickWAV(duration: 20, clickAt: 10, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 200)

        let argmax = try XCTUnwrap(peaks.indices.max(by: { peaks[$0] < peaks[$1] }))
        XCTAssertEqual(argmax, 100, accuracy: 1, "48k source resampled to 44.1k must not shift the click")
    }

    /// A click near the end of the file must not be dropped or displaced —
    /// guards the accumulator's tail behavior when the decoded sample count
    /// differs from the duration-based estimate.
    func test_peaks_clickNearEnd_landsInLastBuckets() async throws {
        let url = try SilentAudioFixture.makeClickWAV(duration: 20, clickAt: 19.9)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 200)

        let argmax = try XCTUnwrap(peaks.indices.max(by: { peaks[$0] < peaks[$1] }))
        XCTAssertEqual(argmax, 199, accuracy: 1, "click at 19.9s of 20s must land at bucket ~199/200")
        XCTAssertGreaterThan(peaks[argmax], 0.9, "the tail click must survive, not be silently dropped")
    }

    // MARK: - Music-only / channel exclusion (#715)

    /// Excluding the loud ch1 tone from a 2-channel file must produce peaks that
    /// differ from the all-channel downmix AND that match the ch0-only content
    /// (the "music" side).
    func test_peaks_excludingChannel_differsFromAllChannelPeaks() async throws {
        // ch0: quiet music-like sine, ch1: full-scale tone (audibly dominant)
        let url = try SilentAudioFixture.makeStereoWAV(
            duration: 1,
            fillCh0: { frame, sr in 0.1 * sin(2 * .pi * 440 * Double(frame) / sr) },
            fillCh1: { frame, sr in sin(2 * .pi * 1000 * Double(frame) / sr) }
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let allChannelPeaks = try await WaveformGenerator.peaks(for: asset, resolution: 32)
        let musicOnlyPeaks = try await WaveformGenerator.peaks(for: asset, resolution: 32, excludingChannel: 1)

        // ch1 dominates the mix, so excluding it changes the peaks significantly.
        let allMax = allChannelPeaks.max() ?? 0
        let musicMax = musicOnlyPeaks.max() ?? 0
        XCTAssertGreaterThan(allMax, 0.5, "all-channel peaks must reflect the loud ch1 tone")
        XCTAssertGreaterThan(musicMax, 0.5, "music-only peaks normalized to ch0 content must reach 1.0 after normalization")
        // The raw (pre-normalization) content of ch0 is ~10× quieter than ch1, so
        // with both channels the mix is dominated by ch1; excluding ch1 gives a
        // different shape. We assert the bucket arrays are not identical.
        XCTAssertNotEqual(
            allChannelPeaks,
            musicOnlyPeaks,
            "excluding the loud ch1 must change the peaks array"
        )
    }

    /// The `excludingChannel: nil` path must produce **byte-identical** output to
    /// the pre-existing `peaks(for:resolution:)` call — the new code path must
    /// not perturb the default behavior.
    func test_peaks_noExclusion_isIdenticalToDefault() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let defaultPeaks = try await WaveformGenerator.peaks(for: asset, resolution: 64)
        let explicitNilPeaks = try await WaveformGenerator.peaks(for: asset, resolution: 64, excludingChannel: nil)

        XCTAssertEqual(
            defaultPeaks,
            explicitNilPeaks,
            "excludingChannel: nil must produce identical output to the default call"
        )
    }

    /// Excluding channel 0 from a 2-channel file must produce the ch1-only content
    /// (the mirror of the previous test, confirming the exclusion is channel-specific).
    func test_peaks_excludingChannel0_reflectsCh1Content() async throws {
        // ch0: silence, ch1: loud full-scale sine
        let url = try SilentAudioFixture.makeStereoWAV(
            duration: 1,
            fillCh0: { _, _ in 0.0 },
            fillCh1: { frame, sr in sin(2 * .pi * 440 * Double(frame) / sr) }
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let musicOnlyPeaks = try await WaveformGenerator.peaks(for: asset, resolution: 32, excludingChannel: 0)

        XCTAssertGreaterThan(
            musicOnlyPeaks.max() ?? 0,
            0.5,
            "ch1 content (loud sine) must survive when ch0 (silence) is excluded"
        )
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
