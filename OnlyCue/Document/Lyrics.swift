import Foundation

/// The timestamped lyrics attached to one `MediaItem`. A reference / HUD layer,
/// decoupled from cues (ADR-022).
///
/// Two clocks: a `LyricLine.time` is SONG-relative, and `offsetSeconds` is the
/// media playback time at which the song begins — an imported file with a
/// one-minute redundant head gets `offsetSeconds = 60`. `effectiveTime` composes
/// the two. The offset is a non-destructive display addend: it never mutates a
/// line's stored `time`, so resetting it to 0 restores the original sync.
struct Lyrics: Codable, Equatable {
    private(set) var lines: [LyricLine]
    var offsetSeconds: TimeInterval

    static let empty = Self(lines: [], offsetSeconds: 0)

    init(lines: [LyricLine], offsetSeconds: TimeInterval) {
        self.lines = lines.sorted { $0.time < $1.time }
        self.offsetSeconds = offsetSeconds
    }

    /// Route decode through the normalizing init so `lines` is always sorted.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lines: try container.decode([LyricLine].self, forKey: .lines),
            offsetSeconds: try container.decode(TimeInterval.self, forKey: .offsetSeconds)
        )
    }

    private enum CodingKeys: String, CodingKey { case lines, offsetSeconds }

    // MARK: - Queries

    /// The media playback time of `line` — its song-relative `time` shifted by
    /// the offset, clamped `>= 0` so a negative offset can't produce a negative
    /// time.
    func effectiveTime(of line: LyricLine) -> TimeInterval {
        max(0, line.time + offsetSeconds)
    }

    /// The line "active" at `mediaSeconds` — the largest `effectiveTime <=
    /// mediaSeconds`. `nil` before the first line; the last line persists once
    /// the playhead is past it. Mirrors `MediaItem.activeCue(at:)`.
    func activeLine(atMediaSeconds mediaSeconds: TimeInterval) -> LyricLine? {
        lines.filter { effectiveTime(of: $0) <= mediaSeconds }
            .max { effectiveTime(of: $0) < effectiveTime(of: $1) }
    }

    /// The line immediately after the one active at `mediaSeconds`; `nil` once
    /// the playhead is past the last line.
    func nextLine(afterMediaSeconds mediaSeconds: TimeInterval) -> LyricLine? {
        lines.filter { effectiveTime(of: $0) > mediaSeconds }
            .min { effectiveTime(of: $0) < effectiveTime(of: $1) }
    }

    // MARK: - Transforms (return a copy)

    /// A copy with `lines` replaced (re-sorted by the init).
    func settingLines(_ newLines: [LyricLine]) -> Self {
        Self(lines: newLines, offsetSeconds: offsetSeconds)
    }

    /// A copy with the offset replaced.
    func settingOffset(_ newOffset: TimeInterval) -> Self {
        Self(lines: lines, offsetSeconds: newOffset)
    }

    // MARK: - Plain-text parsing

    /// Splits pasted plain text into untimed lyric lines — one row per text
    /// line, blank lines preserved as empty-`text` rows, every row stamped
    /// `time = 0`. CRLF / lone-CR line endings are normalized to LF first
    /// (Swift fuses `\r\n` into a single grapheme, so a bare `\n` split misses
    /// it).
    static func untimedLines(fromPlainText text: String) -> [LyricLine] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map {
            LyricLine(time: 0, text: String($0))
        }
    }
}
