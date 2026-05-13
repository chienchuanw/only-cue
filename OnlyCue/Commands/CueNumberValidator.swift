import Foundation

/// grandMA2-shaped validation for cue-number assignments. Pure function over
/// `[Cue]` + a target cue id + a candidate number; centralized so every code
/// path that sets a number (`CueCommands.setCueNumber`, list-cell commits,
/// inspector commits) gets the same rules.
enum CueNumberValidator {

    enum Result: Equatable {
        case ok
        case invalidFormat
        case duplicate
        /// Either bound is `nil` when the target cue has no numbered time-neighbor
        /// on that side (e.g. it's the earliest numbered cue → no `lowerExclusive`).
        case outOfRange(lowerExclusive: Double?, upperExclusive: Double?)
    }

    /// Minimum / maximum permitted by grandMA2 cue numbering: 0.001 to 9999.999
    /// inclusive, with at most three decimal places.
    static let minimum: Double = 0.001
    static let maximum: Double = 9999.999

    /// Validate `candidate` as the new `cueNumber` for the cue with id `cueID`
    /// in `cues`. `nil` clears the number and is always allowed. Self-equal
    /// commits (committing the cue's existing number to itself) return `.ok`.
    static func validate(candidate: Double?, for cueID: Cue.ID, in cues: [Cue]) -> Result {
        guard let candidate else { return .ok }

        guard isWellFormatted(candidate) else { return .invalidFormat }

        let target = cues.first(where: { $0.id == cueID })

        // Uniqueness — any other cue with this exact number is a duplicate.
        // A cue committing its own current number to itself is allowed.
        if cues.contains(where: { $0.id != cueID && $0.cueNumber == candidate }) {
            return .duplicate
        }

        // Strictly ascending vs immediate numbered time-neighbors.
        // Unnumbered cues (including the target if currently nil) are skipped
        // when picking neighbors. Missing neighbor → open bound on that side.
        if let target {
            let numberedNeighbors = cues
                .filter { $0.id != cueID }
                .compactMap { cue -> (TimeInterval, Double)? in
                    cue.cueNumber.map { (cue.time, $0) }
                }
            let prev = numberedNeighbors
                .filter { $0.0 < target.time }
                .max(by: { $0.0 < $1.0 })?
                .1
            let next = numberedNeighbors
                .filter { $0.0 > target.time }
                .min(by: { $0.0 < $1.0 })?
                .1
            if let prev, !(prev < candidate) {
                return .outOfRange(lowerExclusive: prev, upperExclusive: next)
            }
            if let next, !(candidate < next) {
                return .outOfRange(lowerExclusive: prev, upperExclusive: next)
            }
        }

        return .ok
    }

    private static func isWellFormatted(_ n: Double) -> Bool {
        guard n.isFinite else { return false }
        guard n >= minimum, n <= maximum else { return false }
        // Three-decimal-place check via integer round-trip on n * 1000.
        let scaled = n * 1000
        return scaled.rounded() == scaled
    }
}
