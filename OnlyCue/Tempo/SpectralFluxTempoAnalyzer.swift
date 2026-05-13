import Foundation

/// On-device tempo + downbeat-phase estimator (epic #199): a per-hop onset
/// envelope → autocorrelation tempo histogram (with octave-error resolution
/// biased toward a plausible BPM range) → bar-length pulse-train phase alignment.
///
/// v1 derives the onset envelope from a broadband **energy-novelty** function
/// (half-wave-rectified first difference of per-frame log-energy) — a coarser,
/// FFT-free stand-in for true per-bin spectral flux; the pipeline shape is the
/// same, and a true STFT spectral-flux onset (or a Core ML onset model) is a
/// drop-in upgrade behind the `TempoAnalyzer` protocol (ADR-020). Pure and
/// deterministic given its inputs — the engine/device side is `AudioSampleReader`.
struct SpectralFluxTempoAnalyzer: TempoAnalyzer {

    private static let frameSize = 1024
    private static let hopSize = 512
    private static let minBPM = 40.0
    private static let maxBPM = 240.0
    private static let plausibleBPM = 90.0...160.0
    /// Autocorrelation coefficient at the best lag must reach this for a tempo to
    /// be reported — below it the signal has no clear beat (silence, drone, noise).
    private static let confidenceFloor = 0.12

    func analyze(
        samples: [Float],
        sampleRate: Double,
        beatsPerBar: Int,
        bpmHint: ClosedRange<Double>?
    ) async -> TempoEstimate? {
        Self.estimate(samples: samples, sampleRate: sampleRate, beatsPerBar: max(1, beatsPerBar), bpmHint: bpmHint)
    }

    // MARK: - Pure pipeline (deterministic given the inputs)

    static func estimate(
        samples: [Float],
        sampleRate: Double,
        beatsPerBar: Int,
        bpmHint: ClosedRange<Double>?
    ) -> TempoEstimate? {
        guard sampleRate > 0, let onset = onsetEnvelope(samples: samples, sampleRate: sampleRate) else { return nil }
        guard let tempo = tempo(fromOnset: onset.values, onsetRate: onset.rate, bpmHint: bpmHint) else { return nil }
        let beatSamples = onset.rate * 60.0 / tempo.bpm
        guard beatSamples.isFinite, beatSamples > 1 else { return nil }
        let offsetSamples = downbeatOffset(onset: onset.values, beatSamples: beatSamples, beatsPerBar: beatsPerBar)
        let barSeconds = beatSamples * Double(beatsPerBar) / onset.rate
        var offset = offsetSamples / onset.rate
        if barSeconds > 0 { offset = offset.truncatingRemainder(dividingBy: barSeconds) }
        return TempoEstimate(bpm: tempo.bpm, downbeatOffsetSeconds: max(0, offset), confidence: tempo.confidence)
    }

    /// Half-wave-rectified first difference of per-frame log-energy, plus the hop
    /// rate (Hz). `nil` when the input is too short to form a usable envelope.
    static func onsetEnvelope(samples: [Float], sampleRate: Double) -> (values: [Float], rate: Double)? {
        guard sampleRate > 0, samples.count >= frameSize + hopSize else { return nil }
        var logEnergies: [Float] = []
        var start = 0
        while start + frameSize <= samples.count {
            var sumSquares: Float = 0
            for sampleIndex in start..<(start + frameSize) { sumSquares += samples[sampleIndex] * samples[sampleIndex] }
            logEnergies.append(log(sumSquares / Float(frameSize) + 1e-9))
            start += hopSize
        }
        guard logEnergies.count >= 9 else { return nil }
        var envelope: [Float] = []
        envelope.reserveCapacity(logEnergies.count - 1)
        for hop in 1..<logEnergies.count { envelope.append(max(0, logEnergies[hop] - logEnergies[hop - 1])) }
        return (envelope, sampleRate / Double(hopSize))
    }

    /// Autocorrelation-based tempo (BPM) + 0…1 confidence, or `nil` when there's
    /// no clear periodicity.
    static func tempo(fromOnset onset: [Float], onsetRate: Double, bpmHint: ClosedRange<Double>?) -> (bpm: Double, confidence: Double)? {
        guard onsetRate > 0, onset.count >= 16 else { return nil }
        let mean = onset.reduce(0, +) / Float(onset.count)
        let centered = onset.map { Double($0 - mean) }
        let energy = centered.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-9, let peak = dominantLag(ofCentered: centered, onsetRate: onsetRate) else { return nil }
        let coeff = peak.ac[peak.lag] / energy
        guard coeff >= confidenceFloor else { return nil }
        let refined = parabolicPeak(peak.ac, around: peak.lag, lagRange: peak.range)
        let resolved = resolveOctave(refined, ac: peak.ac, lagRange: peak.range, onsetRate: onsetRate, hint: bpmHint ?? plausibleBPM)
        return (60.0 * onsetRate / resolved, min(1, coeff / 0.5))
    }

    // MARK: - Internals

    /// The autocorrelation of the centered onset envelope over the searched lag
    /// range, plus the best lag in it.
    private struct DominantLag {
        let lag: Int
        let ac: [Double]
        let range: ClosedRange<Int>
    }

    private static func dominantLag(ofCentered centered: [Double], onsetRate: Double) -> DominantLag? {
        let lagMin = max(1, Int((onsetRate * 60.0 / maxBPM).rounded()))
        let lagMax = min(centered.count - 2, Int((onsetRate * 60.0 / minBPM).rounded()))
        guard lagMax > lagMin else { return nil }
        let range = lagMin...lagMax
        var ac = [Double](repeating: 0, count: lagMax + 1)
        for lag in range {
            var sum = 0.0
            for tap in 0..<(centered.count - lag) { sum += centered[tap] * centered[tap + lag] }
            ac[lag] = sum
        }
        guard let best = range.max(by: { ac[$0] < ac[$1] }), ac[best] > 0 else { return nil }
        return DominantLag(lag: best, ac: ac, range: range)
    }

    private static func parabolicPeak(_ ac: [Double], around index: Int, lagRange: ClosedRange<Int>) -> Double {
        guard index > lagRange.lowerBound, index < lagRange.upperBound else { return Double(index) }
        let denom = ac[index - 1] - 2 * ac[index] + ac[index + 1]
        guard abs(denom) > 1e-12 else { return Double(index) }
        return Double(index) + max(-0.5, min(0.5, 0.5 * (ac[index - 1] - ac[index + 1]) / denom))
    }

    private static func resolveOctave(
        _ lag: Double,
        ac: [Double],
        lagRange: ClosedRange<Int>,
        onsetRate: Double,
        hint: ClosedRange<Double>
    ) -> Double {
        let candidates = [lag, lag / 2, lag * 2, lag / 3, lag * 3]
            .filter { Double(lagRange.lowerBound) <= $0 && $0 <= Double(lagRange.upperBound) }
        let score: (Double) -> Double = { value in
            let lower = max(lagRange.lowerBound, Int(value.rounded(.down)))
            let upper = min(lagRange.upperBound, lower + 1)
            let frac: Double = value - Double(lower)
            return ac[lower] * (1.0 - frac) + ac[upper] * frac
        }
        let inHint = candidates.filter { hint.contains(60.0 * onsetRate / $0) }
        return inHint.max(by: { score($0) < score($1) }) ?? lag
    }

    /// The onset-envelope-domain offset of the first downbeat: slides a bar-length
    /// pulse train (downbeats weighted higher) and keeps the strongest alignment.
    private static func downbeatOffset(onset: [Float], beatSamples: Double, beatsPerBar: Int) -> Double {
        let barSamples = beatSamples * Double(beatsPerBar)
        guard barSamples.isFinite, barSamples >= 1 else { return 0 }
        let beatCount = max(1, Int(Double(onset.count) / beatSamples))
        var bestOffset = 0.0
        var bestScore = -Double.greatestFiniteMagnitude
        var offset = 0.0
        while offset < barSamples {
            var sum = 0.0
            for beat in 0..<beatCount {
                let idx = Int((offset + Double(beat) * beatSamples).rounded())
                guard idx >= 0, idx < onset.count else { continue }
                sum += Double(onset[idx]) * (beat % beatsPerBar == 0 ? 2.0 : 1.0)
            }
            if sum > bestScore { bestScore = sum; bestOffset = offset }
            offset += 1
        }
        return bestOffset
    }
}
