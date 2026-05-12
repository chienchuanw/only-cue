import XCTest
@testable import OnlyCue

final class SpectralFluxTempoAnalyzerTests: XCTestCase {

    private let sampleRate = 48_000.0

    /// A synthetic click track: a short full-energy burst at every beat (downbeats
    /// twice as loud), starting `phaseSeconds` into the timeline.
    private func clickTrack(
        bpm: Double, beatsPerBar: Int, durationSeconds: Double, phaseSeconds: Double = 0
    ) -> [Float] {
        let count = Int(durationSeconds * sampleRate)
        var samples = [Float](repeating: 0, count: count)
        let beatSamples = 60.0 / bpm * sampleRate
        let burstLen = 256
        var beat = 0
        while true {
            let start = Int((phaseSeconds * sampleRate + Double(beat) * beatSamples).rounded())
            if start >= count { break }
            if start >= 0 {
                let amp: Float = beat % beatsPerBar == 0 ? 1.0 : 0.5
                for sample in 0..<burstLen where start + sample < count { samples[start + sample] = amp }
            }
            beat += 1
        }
        return samples
    }

    /// Deterministic pseudo-random noise in [-1, 1] (an LCG, so the test is repeatable).
    private func deterministicNoise(seconds: Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        var out = [Float](repeating: 0, count: count)
        for sample in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            out[sample] = Float(Double(state >> 33) / Double(1 << 31) * 2 - 1)
        }
        return out
    }

    private func estimate(_ samples: [Float], beatsPerBar: Int = 4, hint: ClosedRange<Double>? = nil) -> TempoEstimate? {
        SpectralFluxTempoAnalyzer.estimate(samples: samples, sampleRate: sampleRate, beatsPerBar: beatsPerBar, bpmHint: hint)
    }

    func test_estimate_recoversTheTempoOfACleanClickTrack() throws {
        let estimate = try XCTUnwrap(estimate(clickTrack(bpm: 125, beatsPerBar: 4, durationSeconds: 16)))
        XCTAssertEqual(estimate.bpm, 125, accuracy: 2.5)
        XCTAssertGreaterThan(estimate.confidence, 0.5)
    }

    func test_estimate_recoversTheDownbeatPhase() throws {
        let phase = 0.12
        let estimate = try XCTUnwrap(estimate(clickTrack(bpm: 125, beatsPerBar: 4, durationSeconds: 16, phaseSeconds: phase)))
        XCTAssertEqual(estimate.bpm, 125, accuracy: 2.5)
        // Within roughly a quarter of a beat (a beat is 0.48 s at 125 BPM).
        XCTAssertEqual(estimate.downbeatOffsetSeconds, phase, accuracy: 0.12)
    }

    func test_estimate_resolvesOctaveErrorTowardThePlausibleRange() throws {
        // Clicks at the 250-BPM rate, all equal: the raw periodicity is 250 BPM, but
        // the default hint (90–160) should pull the reported tempo to 125.
        let estimate = try XCTUnwrap(estimate(clickTrack(bpm: 250, beatsPerBar: 4, durationSeconds: 16)))
        XCTAssertEqual(estimate.bpm, 125, accuracy: 4)
    }

    func test_estimate_returnsNilForSilence() {
        XCTAssertNil(estimate([Float](repeating: 0, count: 96_000)))
    }

    func test_estimate_returnsNilForDeterministicNoise() {
        XCTAssertNil(estimate(deterministicNoise(seconds: 14)))
    }

    func test_estimate_returnsNilForTooShortInput() {
        XCTAssertNil(estimate([Float](repeating: 0.1, count: 1_000)))
    }

    func test_estimate_handlesATempoChangeWhenHalvesAreAnalyzedSeparately() throws {
        let first = try XCTUnwrap(estimate(clickTrack(bpm: 125, beatsPerBar: 4, durationSeconds: 14)))
        let second = try XCTUnwrap(estimate(clickTrack(bpm: 156.25, beatsPerBar: 4, durationSeconds: 14)))
        XCTAssertEqual(first.bpm, 125, accuracy: 3)
        XCTAssertEqual(second.bpm, 156.25, accuracy: 3)
    }

    func test_analyze_async_delegatesToEstimate() async throws {
        let analyzer = SpectralFluxTempoAnalyzer()
        let samples = clickTrack(bpm: 125, beatsPerBar: 4, durationSeconds: 14)
        let result = await analyzer.analyze(samples: samples, sampleRate: sampleRate, beatsPerBar: 4, bpmHint: nil)
        let estimate = try XCTUnwrap(result)
        XCTAssertEqual(estimate.bpm, 125, accuracy: 3)
    }
}
