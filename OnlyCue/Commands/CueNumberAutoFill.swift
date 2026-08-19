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
        for i in stride(from: ordered.count - 1, through: 0, by: -1) {
            nextExisting[i] = running
            if let number = ordered[i].cueNumber { running = number }
        }

        var result: [Cue.ID: Double] = [:]
        var lower: Double?  // nearest number before this slot (existing or just-assigned)
        for (i, cue) in ordered.enumerated() {
            guard cue.cueNumber == nil else { lower = cue.cueNumber; continue }
            let value = pick(lower: lower, upper: nextExisting[i], used: &used)
            result[cue.id] = value
            lower = value
        }
        return result
    }

    private static func key(_ number: Double) -> Int { Int((number * 1000).rounded()) }

    private static func round3(_ number: Double) -> Double { (number * 1000).rounded() / 1000 }

    /// First free number strictly between `lower` and `upper` (either may be open),
    /// preferring whole numbers, then a `+0.1` step from the lower bound, then a
    /// binary-subdivision fallback if `0.1` steps overrun a tight upper bound.
    private static func pick(lower: Double?, upper: Double?, used: inout Set<Int>) -> Double {
        func take(_ value: Double) -> Double { used.insert(key(value)); return value }

        var candidate = max(lower.map { Int(floor($0)) + 1 } ?? 1, 1)
        while upper == nil || Double(candidate) < upper! {
            if !used.contains(key(Double(candidate))) { return take(Double(candidate)) }
            candidate += 1
        }

        let base = lower ?? 0
        var step = 1
        while true {
            let value = round3(base + Double(step) * 0.1)
            if let upper, value >= upper { break }
            if value > base, !used.contains(key(value)) { return take(value) }
            step += 1
        }

        // Tight bound: subdivide (lower, upper) until a free slot appears.
        var high = upper ?? (base + 1)
        for _ in 0..<20 {
            let mid = round3((base + high) / 2)
            if mid > base, mid < (upper ?? .infinity), !used.contains(key(mid)) { return take(mid) }
            high = mid
        }
        return take(round3((base + (upper ?? base + 1)) / 2))
    }
}
