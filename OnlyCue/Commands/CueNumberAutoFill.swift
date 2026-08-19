import Foundation

/// Fills only the `nil` `cueNumber`s of a cue list so a grandMA2 push always has a
/// unique, ordered number per cue (#763). User-entered numbers are never changed:
/// each gap is filled integer-first (`[1, _, 3]` → `2`), falling back to a fractional
/// step from the lower bound when no whole number fits (`[1, _, 2]` → `1.1`). Cues are
/// processed in time order and each assigned value becomes the lower bound of the next,
/// so consecutive gaps stay strictly increasing and never collide with existing numbers.
enum CueNumberAutoFill {

    /// `cue.id -> assigned number` for the nil-numbered cues only. Numbered cues and an
    /// empty list produce no entries.
    static func assignments(for cues: [Cue]) -> [Cue.ID: Double] {
        // Stable time order (original index breaks time ties).
        let ordered = cues.enumerated()
            .sorted { lhs, rhs in
                lhs.element.time == rhs.element.time ? lhs.offset < rhs.offset : lhs.element.time < rhs.element.time
            }
            .map(\.element)

        // Seed the used set (integer-thousandths, matching the pre-flight's rounding).
        var used = Set(ordered.compactMap { $0.cueNumber.map(key) })

        // Upper bound for each slot = nearest *existing* number strictly after it.
        var nextExisting = [Double?](repeating: nil, count: ordered.count)
        var running: Double?
        for index in stride(from: ordered.count - 1, through: 0, by: -1) {
            nextExisting[index] = running
            if let number = ordered[index].cueNumber { running = number }
        }

        var result: [Cue.ID: Double] = [:]
        var lower: Double?  // nearest number before this slot (existing or just-assigned)
        for (index, cue) in ordered.enumerated() {
            guard cue.cueNumber == nil else { lower = cue.cueNumber; continue }
            // No representable unique number in this interval (e.g. a sub-thousandth gap or
            // numbers running backwards vs. time) → leave the cue nil for the pre-flight to
            // report, rather than fabricate a duplicate or an out-of-range value.
            guard let value = pick(lower: lower, upper: nextExisting[index], used: &used) else { continue }
            result[cue.id] = value
            lower = value
        }
        return result
    }

    /// Smallest legal MA2 cue number.
    private static let minNumber = 0.001

    private static func key(_ number: Double) -> Int { Int((number * 1000).rounded()) }

    private static func round3(_ number: Double) -> Double { (number * 1000).rounded() / 1000 }

    /// First free, legal number strictly between `lower` and `upper` (either may be open),
    /// preferring whole numbers, then a `+0.1` step from the lower bound, then a
    /// binary-subdivision fallback for a tight upper bound. Returns `nil` when the interval
    /// holds no unique thousandth `>= minNumber` — every candidate is validated by `fits`,
    /// so the result can never duplicate an existing number or fall out of range.
    private static func pick(lower: Double?, upper: Double?, used: inout Set<Int>) -> Double? {
        let base = lower ?? 0
        func fits(_ value: Double) -> Bool {
            value >= minNumber && value > base && (upper.map { value < $0 } ?? true) && !used.contains(key(value))
        }
        func take(_ value: Double) -> Double { used.insert(key(value)); return value }

        // Cue numbers are always positive, so floor(lower)+1 >= 1 (and 1 when open).
        var candidate = lower.map { Int(floor($0)) + 1 } ?? 1
        while upper.map({ Double(candidate) < $0 }) ?? true {
            if fits(Double(candidate)) { return take(Double(candidate)) }
            candidate += 1
        }

        // +0.1 steps from the lower bound (upper is non-nil here — the integer scan above
        // never exits for an open upper).
        var step = 1
        while let upper, round3(base + Double(step) * 0.1) < upper {
            let value = round3(base + Double(step) * 0.1)
            if fits(value) { return take(value) }
            step += 1
        }

        // Tight bound: subdivide (base, upper) looking for a free thousandth.
        guard let upper else { return nil }
        var high = upper
        for _ in 0..<40 {
            let mid = round3((base + high) / 2)
            if fits(mid) { return take(mid) }
            if high - base < minNumber { break }  // gap narrower than the thousandths grid
            high = mid
        }
        return nil
    }
}
