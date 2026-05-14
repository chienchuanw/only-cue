import Foundation

/// The beat/bar grid rendered on the waveform and used as a snap target. Derived
/// at read time from the item's cues: each cue with a non-nil `bpm` opens a
/// constant-tempo segment running until the next BPM-bearing cue (or
/// `itemDuration`). The cue's own time is bar 1, beat 1 — no separate downbeat
/// offset. `beatsPerBar` is inherited from the previous segment when the cue
/// leaves it `nil`; defaulted to 4 if no upstream meter exists.
///
/// Replaces `TempoMap` (v10) as the visual + snap substrate in v11 (#245).
/// Pure value type.
struct DerivedTempoGrid: Equatable {

    private static let defaultBeatsPerBar = 4
    private static let epsilon: TimeInterval = 1e-9

    struct Segment: Equatable {
        let startSeconds: TimeInterval
        let bpm: Double
        let beatsPerBar: Int

        var beatDuration: TimeInterval { 60.0 / bpm }
        var barDuration: TimeInterval { beatDuration * Double(beatsPerBar) }
    }

    let segments: [Segment]

    var isEmpty: Bool { segments.isEmpty }

    static func from(cues: [Cue]) -> Self {
        let bpmCues = cues
            .filter { $0.bpm != nil }
            .sorted { $0.time < $1.time }
        guard !bpmCues.isEmpty else { return Self(segments: []) }
        var built: [Segment] = []
        for cue in bpmCues {
            guard let bpm = cue.bpm else { continue }
            let meter = cue.beatsPerBar ?? built.last?.beatsPerBar ?? defaultBeatsPerBar
            let clampedBPM = min(max(bpm, 20), 400)
            let clampedMeter = max(1, min(meter, 16))
            let startSeconds = max(0, cue.time)
            // De-dup co-located BPM cues: the last one wins (matches the user's
            // mental model of "most recent edit takes effect"). Without this,
            // a zero-width earlier segment would contribute no beats and the
            // earlier cue's tempo would silently disappear.
            if let last = built.last, abs(last.startSeconds - startSeconds) < Self.epsilon {
                built[built.count - 1] = Segment(
                    startSeconds: startSeconds,
                    bpm: clampedBPM,
                    beatsPerBar: clampedMeter
                )
            } else {
                built.append(Segment(
                    startSeconds: startSeconds,
                    bpm: clampedBPM,
                    beatsPerBar: clampedMeter
                ))
            }
        }
        return Self(segments: built)
    }

    private func segmentEndSeconds(at index: Int, itemDuration: TimeInterval) -> TimeInterval {
        index + 1 < segments.count ? segments[index + 1].startSeconds : itemDuration
    }

    func beatTimes(
        in range: ClosedRange<TimeInterval>,
        itemDuration: TimeInterval
    ) -> [(time: TimeInterval, isDownbeat: Bool)] {
        guard !segments.isEmpty else { return [] }
        var out: [(time: TimeInterval, isDownbeat: Bool)] = []
        for (index, segment) in segments.enumerated() {
            let spanEnd = segmentEndSeconds(at: index, itemDuration: itemDuration)
            let isLast = index + 1 == segments.count
            out.append(contentsOf: beats(in: segment, spanEnd: spanEnd, isLast: isLast, clampedTo: range))
        }
        return out
    }

    func barTimes(in range: ClosedRange<TimeInterval>, itemDuration: TimeInterval) -> [TimeInterval] {
        beatTimes(in: range, itemDuration: itemDuration).filter(\.isDownbeat).map(\.time)
    }

    func nearestBeat(toSeconds seconds: TimeInterval, itemDuration: TimeInterval) -> TimeInterval? {
        nearestGridLine(toSeconds: seconds, itemDuration: itemDuration, stride: \.beatDuration)
    }

    func nearestBar(toSeconds seconds: TimeInterval, itemDuration: TimeInterval) -> TimeInterval? {
        nearestGridLine(toSeconds: seconds, itemDuration: itemDuration, stride: \.barDuration)
    }

    // MARK: - Internals

    private func beats(
        in segment: Segment,
        spanEnd: TimeInterval,
        isLast: Bool,
        clampedTo range: ClosedRange<TimeInterval>
    ) -> [(time: TimeInterval, isDownbeat: Bool)] {
        let lower = max(range.lowerBound, segment.startSeconds)
        let upper = min(range.upperBound, spanEnd)
        guard upper >= lower - Self.epsilon else { return [] }
        let step = segment.beatDuration
        let anchor = segment.startSeconds
        let firstIndex = Int(((lower - anchor) / step).rounded(.up))
        // Segment span is half-open EXCEPT for the last segment, which closes
        // at itemDuration — a beat landing exactly on itemDuration is included.
        let spanCeiling = isLast ? spanEnd : spanEnd - Self.epsilon
        let lastIndexInSpan = Int(((spanCeiling - anchor) / step).rounded(.down))
        let lastIndexInRange = Int(((upper - anchor) / step).rounded(.down))
        let lastIndex = min(lastIndexInSpan, lastIndexInRange)
        guard firstIndex <= lastIndex else { return [] }
        var result: [(time: TimeInterval, isDownbeat: Bool)] = []
        for beatIndex in firstIndex...lastIndex {
            let time = anchor + Double(beatIndex) * step
            guard time >= segment.startSeconds - Self.epsilon else { continue }
            // Half-open at segment-to-segment boundaries: the boundary belongs
            // to the next segment. The segment's own first beat (beatIndex==0)
            // lives here. At the item's trailing end (isLast), the boundary is
            // closed.
            if !isLast && beatIndex > 0 && time >= spanEnd - Self.epsilon { continue }
            let modulo = ((beatIndex % segment.beatsPerBar) + segment.beatsPerBar) % segment.beatsPerBar
            let isDownbeat = modulo == 0
            result.append((time: time, isDownbeat: isDownbeat))
        }
        return result
    }

    private func nearestGridLine(
        toSeconds seconds: TimeInterval,
        itemDuration: TimeInterval,
        stride keyPath: KeyPath<Segment, TimeInterval>
    ) -> TimeInterval? {
        guard !segments.isEmpty else { return nil }
        var coveringIndex: Int?
        for (index, segment) in segments.enumerated() where segment.startSeconds <= seconds + Self.epsilon {
            coveringIndex = index
        }
        guard let coveringIndex else { return nil }
        let segment = segments[coveringIndex]
        let spanEnd = segmentEndSeconds(at: coveringIndex, itemDuration: itemDuration)
        let step = segment[keyPath: keyPath]
        guard step > 0 else { return segment.startSeconds }
        let anchor = segment.startSeconds
        let rounded = ((seconds - anchor) / step).rounded()
        var candidate = anchor + rounded * step
        if candidate < segment.startSeconds { candidate = segment.startSeconds }
        if candidate >= spanEnd - Self.epsilon {
            let last = ((spanEnd - Self.epsilon - anchor) / step).rounded(.down)
            candidate = anchor + last * step
        }
        // Prefer the next segment's start (its first downbeat / beat boundary)
        // when it's closer than our in-segment candidate.
        if coveringIndex + 1 < segments.count {
            let next = segments[coveringIndex + 1].startSeconds
            if abs(next - seconds) < abs(candidate - seconds) {
                return next
            }
        }
        return max(segment.startSeconds, candidate)
    }
}
