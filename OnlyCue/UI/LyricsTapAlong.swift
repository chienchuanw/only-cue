import Foundation

/// Pure tap-along cursor for the Lyrics Editor. Owns only the cursor index;
/// stamping is a pure transform over the caller's lines so there is one source
/// of truth for the line array (the sheet's draft). Stamping past the last row
/// is a no-op — tap-along only times existing rows.
struct LyricsTapAlong: Equatable {
    private(set) var cursor: Int = 0

    /// Returns `lines` with the cursor row stamped at a SONG-relative time
    /// (`playhead - offset`, clamped `>= 0`, so the line's effective time lands
    /// exactly at `playhead`), and advances the cursor. Returns `lines`
    /// unchanged once the cursor is past the last row.
    mutating func stamping(
        _ lines: [LyricLine],
        playhead: TimeInterval,
        offsetSeconds: TimeInterval
    ) -> [LyricLine] {
        guard lines.indices.contains(cursor) else { return lines }
        var updated = lines
        updated[cursor].time = max(0, playhead - offsetSeconds)
        cursor += 1
        return updated
    }

    /// Moves the cursor up one row without stamping. No-op at the first row.
    mutating func stepBack() {
        cursor = max(0, cursor - 1)
    }
}
