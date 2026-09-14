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

        if cues.contains(where: { $0.id != cueID && $0.cueNumber == candidate }) {
            return .duplicate
        }

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

    /// Is `value` inside the numbering window at all — finite and within
    /// `minimum...maximum`?
    ///
    /// Deliberately weaker than `isWellFormatted`, which additionally demands
    /// the three-decimal round-trip. The boundaries that *coerce* an untrusted
    /// number rather than reject typed input (`Cue.init(from:)`,
    /// `CueCommands.renumberSelected`, `MA2CueNumber`) gate on this window
    /// alone: a fourth decimal place is rounded harmlessly into thousandths by
    /// both MA2 generators, so discarding it would be gratuitous data loss,
    /// whereas a value outside the window has no MA2 meaning and traps or
    /// misformats downstream (#830).
    ///
    /// `isFinite` is stated rather than relied upon: IEEE comparison already
    /// rejects NaN and both infinities through the bounds alone, and dropping it
    /// fails no test on either core (verified by mutation on Swift *and* on the
    /// C# mirror, which behaves identically). It stays because reordering the
    /// bounds or folding them into a clamp helper would silently change the
    /// non-finite answer, and because `FadeTime.clamped` next door needs the
    /// same guard for real — there `min`/`max` would propagate NaN.
    static func isInDomain(_ value: Double) -> Bool {
        value.isFinite && value >= minimum && value <= maximum
    }

    private static func isWellFormatted(_ value: Double) -> Bool {
        guard isInDomain(value) else { return false }
        // Three-decimal-place check via integer round-trip on value * 1000.
        let scaled = value * 1000
        return scaled.rounded() == scaled
    }
}
