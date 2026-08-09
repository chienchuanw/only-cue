import AVFoundation
import XCTest
@testable import OnlyCue

/// Tests for the #732 time-based peak+RMS bucket engine — the new generation
/// path that replaces the fixed-count, pre-normalized `peaks(for:resolution:)`
/// output. Buckets are a fixed wall-clock width (default 10 ms), carry BOTH a
/// peak (max |sample|) and an RMS value, and are **un-normalized** (render-time
/// normalization lands in #734). Progressive delivery is via `bucketStream`.
final class WaveformBucketGeneratorTests: XCTestCase {

    // MARK: - Resolution (time-based, not count-based)

    func test_buckets_countIsCeilOfDurationOverBucketWidth() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 2, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }

        let buckets = try await WaveformGenerator.buckets(for: AVURLAsset(url: url), bucketMillis: 10)

        // 2.000 s / 10 ms = 200 buckets (±1 for duration-rounding at the tail).
        XCTAssertEqual(buckets.count, 200, accuracy: 1)
    }

    func test_buckets_finerWidthYieldsMoreBuckets() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        let coarse = try await WaveformGenerator.buckets(for: asset, bucketMillis: 20)
        let fine = try await WaveformGenerator.buckets(for: asset, bucketMillis: 5)

        XCTAssertEqual(coarse.count, 50, accuracy: 1)
        XCTAssertEqual(fine.count, 200, accuracy: 1)
    }

    // MARK: - Peak + RMS per bucket

    func test_buckets_peakIsAtLeastRMS() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }

        let buckets = try await WaveformGenerator.buckets(for: AVURLAsset(url: url), bucketMillis: 10)

        XCTAssertFalse(buckets.isEmpty)
        for bucket in buckets {
            XCTAssertGreaterThanOrEqual(bucket.peak, bucket.rms, "peak (max |sample|) must be >= RMS")
        }
    }

    /// A full-scale 200 Hz sine (well below the 8 kHz analysis path's 4 kHz
    /// Nyquist) has peak ≈ 1.0 but RMS ≈ 0.707 — the two values must be *separable*,
    /// which is the whole point of storing both (peak finds the transient, RMS
    /// shows loudness). A signal above Nyquist is deliberately not used here: the
    /// resampler would low-pass it away (that is correct engine behaviour).
    func test_buckets_capturePeakAndRMSSeparately() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 2, frequency: 200, amplitude: 1.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let buckets = try await WaveformGenerator.buckets(for: AVURLAsset(url: url), bucketMillis: 10)
        let midPeak = buckets[buckets.count / 2].peak
        let midRMS = buckets[buckets.count / 2].rms

        XCTAssertEqual(midPeak, 1.0, accuracy: 0.1, "peak must catch the full-scale crest")
        XCTAssertEqual(midRMS, 0.707, accuracy: 0.1, "RMS of a full-scale sine is ~0.707, distinct from its peak")
        XCTAssertGreaterThan(midPeak, midRMS * 1.2, "peak and RMS must be separable, not the same number")
    }

    // MARK: - Un-normalized (render-time normalization is #734)

    /// A quiet 0.2-amplitude sine must NOT be scaled up to full height — the
    /// stored buckets are raw. (The old `peaks` path normalized quiet files to
    /// 1.0; this new path deliberately does not.)
    func test_buckets_areUnnormalized() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440, amplitude: 0.2)
        defer { try? FileManager.default.removeItem(at: url) }

        let buckets = try await WaveformGenerator.buckets(for: AVURLAsset(url: url), bucketMillis: 10)
        let maxPeak = buckets.map(\.peak).max() ?? 0

        XCTAssertLessThan(maxPeak, 0.4, "0.2-amplitude input must stay ~0.2, not normalize to 1.0")
        XCTAssertGreaterThan(maxPeak, 0.1, "but the content must still be present")
    }

    func test_buckets_silence_isZero() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let buckets = try await WaveformGenerator.buckets(for: AVURLAsset(url: url), bucketMillis: 10)

        XCTAssertEqual(buckets.map(\.peak).max() ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(buckets.map(\.rms).max() ?? 1, 0, accuracy: 0.001)
    }

    // MARK: - Progressive streaming

    func test_bucketStream_yieldsProgressively_andFinalMatchesCollect() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 3, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        var emissions: [Int] = []
        var last: [WaveformBucket] = []
        for try await snapshot in WaveformGenerator.bucketStream(for: asset, bucketMillis: 10) {
            emissions.append(snapshot.count)
            last = snapshot
        }

        // Snapshots grow monotonically toward the full length.
        XCTAssertEqual(emissions, emissions.sorted(), "each snapshot must be at least as long as the previous")
        XCTAssertGreaterThan(emissions.count, 1, "a 3 s file must stream more than one progress snapshot")

        let collected = try await WaveformGenerator.buckets(for: asset, bucketMillis: 10)
        XCTAssertEqual(last.count, collected.count, "final streamed snapshot must equal the collected result")
    }

    func test_bucketStream_cancellation_stopsWithoutError() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 3, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)

        // Consume a single snapshot then break — the stream must terminate cleanly
        // (its producing task observes termination) without throwing or hanging.
        for try await snapshot in WaveformGenerator.bucketStream(for: asset, bucketMillis: 10) {
            XCTAssertGreaterThanOrEqual(snapshot.count, 0)
            break
        }
    }
}
