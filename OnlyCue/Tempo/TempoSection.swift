import Foundation

/// One constant-tempo span of a media item's tempo map (epic #199): from
/// `startSeconds` until the next section's start (or the item's end), the grid
/// runs at `bpm` with `beatsPerBar` beats to a bar, and the first downbeat sits
/// `downbeatOffsetSeconds` into the span.
///
/// Beats fall at `startSeconds + downbeatOffsetSeconds + j * beatDuration` for
/// every integer `j` (positive *and* negative — the offset may exceed one beat,
/// so a partial bar before the first downbeat is allowed); a beat is a downbeat
/// when `j` is a multiple of `beatsPerBar`.
///
/// `bpm` / `beatsPerBar` are clamped at construction so the derived durations
/// never divide by zero; the *full* normalization (sorting, forcing the first
/// section to time 0, reducing `downbeatOffsetSeconds` into `[0, barDuration)`)
/// is the job of `TempoMap`, which owns the invariants across sections.
struct TempoSection: Codable, Equatable, Identifiable, Sendable {

    static let minBPM = 20.0
    static let maxBPM = 400.0
    static let defaultBPM = 120.0
    static let defaultBeatsPerBar = 4

    let id: UUID
    var startSeconds: TimeInterval
    var bpm: Double
    var beatsPerBar: Int
    var downbeatOffsetSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        startSeconds: TimeInterval,
        bpm: Double = Self.defaultBPM,
        beatsPerBar: Int = Self.defaultBeatsPerBar,
        downbeatOffsetSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.startSeconds = max(0, startSeconds)
        self.bpm = min(max(bpm, Self.minBPM), Self.maxBPM)
        self.beatsPerBar = max(1, beatsPerBar)
        self.downbeatOffsetSeconds = max(0, downbeatOffsetSeconds)
    }

    /// Seconds per beat at this section's tempo.
    var beatDuration: TimeInterval { 60.0 / bpm }

    /// Seconds per bar (`beatsPerBar` beats).
    var barDuration: TimeInterval { beatDuration * Double(beatsPerBar) }

    /// Absolute time of bar 1, beat 1 of this section.
    var firstDownbeatSeconds: TimeInterval { startSeconds + downbeatOffsetSeconds }

    /// A copy with `downbeatOffsetSeconds` reduced into `[0, barDuration)`.
    func reducingDownbeatOffset() -> Self {
        var copy = self
        let bar = barDuration
        copy.downbeatOffsetSeconds = bar > 0 ? downbeatOffsetSeconds.truncatingRemainder(dividingBy: bar) : 0
        if copy.downbeatOffsetSeconds < 0 { copy.downbeatOffsetSeconds += bar }
        return copy
    }

    /// `true` when beat index `j` (relative to `firstDownbeatSeconds`) is a downbeat.
    func isDownbeat(beatIndex index: Int) -> Bool {
        ((index % beatsPerBar) + beatsPerBar) % beatsPerBar == 0
    }
}
