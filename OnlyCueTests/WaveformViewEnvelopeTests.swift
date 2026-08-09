import XCTest
@testable import OnlyCue

/// Render-time normalization for the #734 dual envelope. Both the filled RMS
/// body and the peak outline are normalized by ONE shared divisor — the global
/// peak-max of the loaded buckets (spec §5) — NOT by independent per-statistic
/// maxes. The shared divisor is what guarantees `rms[i] <= peak[i]` at every
/// column, so the filled body can never spill past the peak outline (the
/// artifact independent normalization would produce in sustained/low-crest
/// sections).
final class WaveformViewEnvelopeTests: XCTestCase {

    func test_normalizedEnvelope_bodyNeverExceedsOutline_evenForLowCrestBuckets() {
        // A brief transient sets the global peak max; a sustained low-crest
        // bucket (rms close to its own peak) is the poke-through trap: under
        // INDEPENDENT normalization its rms/maxRMS = 1.0 would tower over its
        // peak/maxPeak = 0.5. The shared divisor keeps the body contained.
        let buckets = [
            WaveformBucket(peak: 1.0, rms: 0.2),   // transient — sets global peak max
            WaveformBucket(peak: 0.5, rms: 0.45)   // sustained pad — low crest factor
        ]
        let env = WaveformView.normalizedEnvelope(buckets: buckets, count: 2)

        XCTAssertEqual(env.rms.count, env.peak.count)
        for index in env.rms.indices {
            XCTAssertLessThanOrEqual(
                env.rms[index],
                env.peak[index] + 1e-6,
                "RMS body column \(index) spilled past the peak outline — divisor not shared"
            )
        }
        // The sustained bucket specifically: shared divisor (max peak = 1.0)
        // leaves the body at 0.45, below its 0.5 outline.
        XCTAssertEqual(env.rms[1], 0.45, accuracy: 1e-6)
        XCTAssertEqual(env.peak[1], 0.5, accuracy: 1e-6)
    }

    func test_normalizedEnvelope_loudestPeakNormalizesToOne_rmsSharesDivisor() {
        let buckets = [
            WaveformBucket(peak: 0.25, rms: 0.1),
            WaveformBucket(peak: 0.8, rms: 0.5),   // loudest peak → global divisor
            WaveformBucket(peak: 0.4, rms: 0.4)
        ]
        let env = WaveformView.normalizedEnvelope(buckets: buckets, count: 3)

        XCTAssertEqual(
            env.peak.max() ?? 0,
            1.0,
            accuracy: 1e-6,
            "the loudest peak must reach 1.0 under the shared divisor"
        )
        // RMS scaled by the SAME 0.8 divisor, not by its own max (0.5).
        XCTAssertEqual(env.rms[1], 0.5 / 0.8, accuracy: 1e-6)
        XCTAssertEqual(env.rms[2], 0.4 / 0.8, accuracy: 1e-6)
    }

    func test_normalizedEnvelope_renderTimeEqualsGlobalMax_whenFullyLoaded() throws {
        // Spec §5: normalizing by "max of loaded" on the full set is identical to
        // dividing the raw collapse by the global peak max — no end-of-load snap.
        let buckets = (0..<20).map { index in
            WaveformBucket(peak: Float(index) / 38, rms: Float(index) / 76)
        }
        let count = 8
        let env = WaveformView.normalizedEnvelope(buckets: buckets, count: count)

        let rawPeak = WaveformPeakBucketer.bucket(peaks: buckets.map(\.peak), into: count)
        let rawRMS = WaveformPeakBucketer.bucketRMS(buckets.map(\.rms), into: count)
        let globalMax = try XCTUnwrap(buckets.map(\.peak).max())
        for index in env.peak.indices {
            XCTAssertEqual(env.peak[index], rawPeak[index] / globalMax, accuracy: 1e-6)
            XCTAssertEqual(env.rms[index], rawRMS[index] / globalMax, accuracy: 1e-6)
        }
    }

    func test_normalizedEnvelope_silence_isFlatWithoutNaN() {
        let buckets = Array(repeating: WaveformBucket(peak: 0, rms: 0), count: 5)
        let env = WaveformView.normalizedEnvelope(buckets: buckets, count: 5)

        XCTAssertFalse(env.rms.contains { $0.isNaN || $0 > 0 })
        XCTAssertFalse(env.peak.contains { $0.isNaN || $0 > 0 })
    }

    func test_normalizedEnvelope_empty_returnsEmpty() {
        let env = WaveformView.normalizedEnvelope(buckets: [], count: 4)
        XCTAssertTrue(env.rms.isEmpty)
        XCTAssertTrue(env.peak.isEmpty)
    }
}
