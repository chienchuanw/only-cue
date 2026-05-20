import Foundation

/// Pure tap-along cursor for the Lyrics Editor. Captures the row order when
/// tap-along starts and walks it by row identity, so re-sorting the draft
/// between taps (`Lyrics` keeps `lines` sorted by `time`) never desyncs the
/// cursor. Stamping past the last row is a no-op — tap-along only times
/// existing rows.
struct LyricsTapAlong: Equatable {
    /// Row IDs in the order they will be stamped — fixed when tap-along starts.
    private let order: [LyricLine.ID]
    private(set) var position: Int = 0

    init(lines: [LyricLine]) {
        order = lines.map(\.id)
    }

    /// The id of the row the next tap will stamp; `nil` once past the last row.
    var cursorID: LyricLine.ID? {
        order.indices.contains(position) ? order[position] : nil
    }

    /// Returns `lines` with the cursor row (located by id) stamped at a
    /// SONG-relative time (`playhead - offset`, clamped `>= 0`), and advances
    /// the cursor. Returns `lines` unchanged once past the last row or if the
    /// cursor row is no longer present.
    mutating func stamping(
        _ lines: [LyricLine],
        playhead: TimeInterval,
        offsetSeconds: TimeInterval
    ) -> [LyricLine] {
        guard let id = cursorID, let index = lines.firstIndex(where: { $0.id == id }) else { return lines }
        var updated = lines
        updated[index].time = max(0, playhead - offsetSeconds)
        position += 1
        return updated
    }

    /// Moves the cursor up one row without stamping. No-op at the first row.
    mutating func stepBack() {
        position = max(0, position - 1)
    }
}
