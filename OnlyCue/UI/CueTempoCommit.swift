import Foundation

/// Pure-Swift helpers for translating the Tempo sheet's draft strings into
/// the `(bpm, beatsPerBar)` pair that gets handed to `CueCommands.setCueTempo`.
/// Kept separate from the SwiftUI view so the commit pipeline can be tested
/// without standing up the view tree.
enum CueTempoCommit {

    /// Resolve the values to save given the current draft strings and the
    /// cue's existing values.
    ///
    /// - Empty BPM commits `(nil, nil)` — clearing BPM also clears beats/bar
    ///   (an orphan meter is meaningless and would corrupt DerivedTempoGrid).
    /// - Non-finite or unparseable BPM reverts to the initial pair so a typo
    ///   cannot wipe a previously-set tempo.
    static func resolve(
        bpmDraft: String,
        beatsPerBarDraft: String,
        initialBPM: Double?,
        initialBeatsPerBar: Int?
    ) -> (bpm: Double?, beatsPerBar: Int?) {
        let trimmedBPM = bpmDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBPM.isEmpty {
            return (nil, nil)
        }
        guard let bpm = Double(trimmedBPM), bpm.isFinite else {
            return (initialBPM, initialBeatsPerBar)
        }
        let trimmedBeats = beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let beats = Int(trimmedBeats) ?? initialBeatsPerBar
        return (bpm, beats)
    }

    /// String to seed `bpmDraft` from a detected estimate. Mirrors how the
    /// inspector formerly displayed the value (rounded to nearest integer).
    static func formatDetectedBPM(_ bpm: Double) -> String {
        String(Int(bpm.rounded()))
    }
}
