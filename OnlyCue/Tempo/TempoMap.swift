import Foundation

/// A media item's tempo map (epic #199): an ordered list of constant-tempo
/// `TempoSection`s. Persisted in `.cuelist` (schema v8). An **empty** map means
/// "no tempo grid"; a non-empty map always covers the item from time 0 (the
/// first section's `startSeconds` is forced to 0) with strictly increasing
/// section starts.
///
/// The map is purely a visual + snap aid — it does not move cues. See ADR-020.
struct TempoMap: Codable, Equatable, Sendable {

    /// A small absolute tolerance for the float comparisons in the grid maths.
    private static let epsilon: TimeInterval = 1e-9

    private(set) var sections: [TempoSection]

    /// An empty map — no grid.
    init() {
        sections = []
    }

    /// Build a normalized map: sections sorted by `startSeconds`, de-duplicated
    /// by start (last wins), the first section forced to start at 0, and each
    /// section's `downbeatOffsetSeconds` reduced into `[0, barDuration)`.
    init(sections raw: [TempoSection]) {
        var sorted = raw
            .map { $0.reducingDownbeatOffset() }
            .sorted { $0.startSeconds < $1.startSeconds }

        // De-dupe equal starts, keeping the last (later edits win).
        var deduped: [TempoSection] = []
        for section in sorted {
            if let last = deduped.last, abs(last.startSeconds - section.startSeconds) < Self.epsilon {
                deduped[deduped.count - 1] = section
            } else {
                deduped.append(section)
            }
        }
        sorted = deduped

        if !sorted.isEmpty {
            sorted[0].startSeconds = 0
        }
        sections = sorted
    }

    var isEmpty: Bool { sections.isEmpty }

    /// A whole-item map with a single section starting at 0.
    static func singleSection(
        bpm: Double = TempoSection.defaultBPM,
        beatsPerBar: Int = TempoSection.defaultBeatsPerBar,
        downbeatOffsetSeconds: TimeInterval = 0
    ) -> Self {
        Self(sections: [
            TempoSection(startSeconds: 0, bpm: bpm, beatsPerBar: beatsPerBar, downbeatOffsetSeconds: downbeatOffsetSeconds)
        ])
    }

    // MARK: - Section lookup

    /// The section covering `seconds` — the one with the greatest `startSeconds <= seconds`
    /// (or the first section if `seconds` is negative). `nil` only when the map is empty.
    func section(atSeconds seconds: TimeInterval) -> TempoSection? {
        guard !sections.isEmpty else { return nil }
        var match = sections[0]
        for section in sections where section.startSeconds <= seconds + Self.epsilon {
            match = section
        }
        return match
    }

    /// Where the given section ends: the next section's `startSeconds`, or `itemDuration`.
    func sectionEndSeconds(for section: TempoSection, itemDuration: TimeInterval) -> TimeInterval {
        guard let index = sections.firstIndex(where: { $0.id == section.id }) else { return itemDuration }
        let nextIndex = index + 1
        return nextIndex < sections.count ? sections[nextIndex].startSeconds : itemDuration
    }

    // MARK: - Grid

    /// Every beat falling in `range`, tagged downbeat-or-not, walking section by section.
    /// Section spans are half-open: a beat exactly on a section boundary belongs to the
    /// section that *starts* there.
    func beatTimes(
        in range: ClosedRange<TimeInterval>,
        itemDuration: TimeInterval
    ) -> [(time: TimeInterval, isDownbeat: Bool)] {
        guard !sections.isEmpty else { return [] }
        var result: [(time: TimeInterval, isDownbeat: Bool)] = []
        for section in sections {
            let spanEnd = sectionEndSeconds(for: section, itemDuration: itemDuration)
            result.append(contentsOf: beats(in: section, spanEnd: spanEnd, clampedTo: range))
        }
        return result
    }

    /// Just the downbeats in `range`.
    func barTimes(in range: ClosedRange<TimeInterval>, itemDuration: TimeInterval) -> [TimeInterval] {
        beatTimes(in: range, itemDuration: itemDuration).filter(\.isDownbeat).map(\.time)
    }

    /// The grid beat nearest `seconds`, clamped to stay inside that beat's section span.
    /// `nil` when the map is empty.
    func nearestBeat(toSeconds seconds: TimeInterval, itemDuration: TimeInterval) -> TimeInterval? {
        nearestGridLine(toSeconds: seconds, itemDuration: itemDuration, stride: \.beatDuration)
    }

    /// The grid downbeat (bar line) nearest `seconds`, clamped to its section span.
    /// `nil` when the map is empty.
    func nearestBar(toSeconds seconds: TimeInterval, itemDuration: TimeInterval) -> TimeInterval? {
        nearestGridLine(toSeconds: seconds, itemDuration: itemDuration, stride: \.barDuration)
    }

    // MARK: - Pure transforms

    /// Insert a section boundary at `seconds`, cloning the covering section's tempo so the
    /// beat (and bar) grid is continuous across the split. On an empty map: returns a
    /// single-section whole-item map (with default tempo). A no-op when `seconds` is at or
    /// before the covering section's start.
    func splitting(atSeconds seconds: TimeInterval) -> Self {
        guard let covering = section(atSeconds: seconds) else { return Self.singleSection() }
        guard seconds > covering.startSeconds + Self.epsilon else { return self }
        let bar = covering.barDuration
        let raw = (covering.firstDownbeatSeconds - seconds).truncatingRemainder(dividingBy: bar)
        let offset = raw < 0 ? raw + bar : raw
        let inserted = TempoSection(
            startSeconds: seconds,
            bpm: covering.bpm,
            beatsPerBar: covering.beatsPerBar,
            downbeatOffsetSeconds: offset
        )
        return Self(sections: sections + [inserted])
    }

    /// Add a section: on an empty map, seeds the whole-item section at 0; otherwise the
    /// same as `splitting(atSeconds:)`.
    func addingSection(atSeconds seconds: TimeInterval) -> Self {
        isEmpty ? Self.singleSection() : splitting(atSeconds: seconds)
    }

    /// Remove the section with `id`. The previous section's span automatically extends to
    /// cover the gap; removing the first section promotes the next to start at 0; removing
    /// the only section yields an empty map.
    func removingSection(_ id: TempoSection.ID) -> Self {
        Self(sections: sections.filter { $0.id != id })
    }

    /// Replace fields on the section with `id` (any argument left `nil` is unchanged) and
    /// re-normalize. Editing the first section's `startSeconds` has no effect — the first
    /// section is always pinned to 0.
    func updatingSection(
        _ id: TempoSection.ID,
        startSeconds: TimeInterval? = nil,
        bpm: Double? = nil,
        beatsPerBar: Int? = nil,
        downbeatOffsetSeconds: TimeInterval? = nil
    ) -> Self {
        let updated = sections.map { section -> TempoSection in
            guard section.id == id else { return section }
            return TempoSection(
                id: section.id,
                startSeconds: startSeconds ?? section.startSeconds,
                bpm: bpm ?? section.bpm,
                beatsPerBar: beatsPerBar ?? section.beatsPerBar,
                downbeatOffsetSeconds: downbeatOffsetSeconds ?? section.downbeatOffsetSeconds
            )
        }
        return Self(sections: updated)
    }

    // MARK: - Internals

    private func beats(
        in section: TempoSection,
        spanEnd: TimeInterval,
        clampedTo range: ClosedRange<TimeInterval>
    ) -> [(time: TimeInterval, isDownbeat: Bool)] {
        let lower = max(range.lowerBound, section.startSeconds)
        let upper = min(range.upperBound, spanEnd)
        guard upper >= lower - Self.epsilon else { return [] }
        let step = section.beatDuration
        let anchor = section.firstDownbeatSeconds
        let firstIndex = Int(((lower - anchor) / step).rounded(.up))
        let lastIndex = Int(((upper - anchor) / step).rounded(.down))
        guard firstIndex <= lastIndex else { return [] }
        var out: [(time: TimeInterval, isDownbeat: Bool)] = []
        for index in firstIndex...lastIndex {
            let time = anchor + Double(index) * step
            guard time >= section.startSeconds - Self.epsilon, time < spanEnd - Self.epsilon else { continue }
            guard time >= range.lowerBound - Self.epsilon, time <= range.upperBound + Self.epsilon else { continue }
            out.append((time: time, isDownbeat: section.isDownbeat(beatIndex: index)))
        }
        return out
    }

    private func nearestGridLine(
        toSeconds seconds: TimeInterval,
        itemDuration: TimeInterval,
        stride keyPath: KeyPath<TempoSection, TimeInterval>
    ) -> TimeInterval? {
        guard let section = section(atSeconds: seconds) else { return nil }
        let spanEnd = sectionEndSeconds(for: section, itemDuration: itemDuration)
        let step = section[keyPath: keyPath]
        guard step > 0 else { return section.startSeconds }
        let anchor = section.firstDownbeatSeconds
        var index = ((seconds - anchor) / step).rounded()
        var time = anchor + index * step
        // Clamp into the half-open section span [startSeconds, spanEnd).
        if time < section.startSeconds {
            index = ((section.startSeconds - anchor) / step).rounded(.up)
            time = anchor + index * step
        }
        if time >= spanEnd - Self.epsilon {
            index = ((spanEnd - Self.epsilon - anchor) / step).rounded(.down)
            time = anchor + index * step
        }
        return max(section.startSeconds, time)
    }
}
