import Foundation

/// The result of estimating tempo for a span of audio: a BPM, the phase of the
/// first downbeat within the span (already reduced into `[0, barDuration)` for
/// the assumed `beatsPerBar`), and a 0…1 confidence the UI can surface as a
/// "low confidence" hint.
struct TempoEstimate: Equatable, Sendable {
    var bpm: Double
    var downbeatOffsetSeconds: TimeInterval
    var confidence: Double
}

/// Estimates tempo for mono PCM. v1 has one implementation
/// (`SpectralFluxTempoAnalyzer`, on-device DSP); the protocol exists so a
/// Core ML / hosted-engine analyzer can replace it later without touching the
/// tempo-map UI or the command layer (ADR-020).
protocol TempoAnalyzer: Sendable {
    /// Estimate tempo for `samples` at `sampleRate`. `beatsPerBar` is the assumed
    /// time-signature numerator, so the analyzer can phase-align downbeats.
    /// `bpmHint` biases octave-error resolution toward a plausible range; pass
    /// `nil` for the default (≈ 90–160 BPM). Returns `nil` when there's no
    /// detectable periodicity (silence, drone, speech).
    func analyze(
        samples: [Float],
        sampleRate: Double,
        beatsPerBar: Int,
        bpmHint: ClosedRange<Double>?
    ) async -> TempoEstimate?
}
