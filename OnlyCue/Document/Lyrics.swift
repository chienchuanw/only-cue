import Foundation

/// The lyrics attached to one `MediaItem`. A reference / HUD layer, decoupled
/// from cues (ADR-022).
///
/// Two clocks: `LyricLine.time` is SONG-relative, `offsetSeconds` is the media
/// playback time at which the song begins. `effectiveTime` composes them. The
/// offset is a non-destructive display addend.
///
/// `lines` is kept in **authoring order** (paste / song order). Placed lines
/// (non-nil `time`) and unplaced lines (`nil`) are interleaved there; the
/// `placedLines` / `unplacedLines` projections split them for the timeline and
/// the queue respectively.
struct Lyrics: Codable, Equatable {
    private(set) var lines: [LyricLine]
    var offsetSeconds: TimeInterval

    static let empty = Self(lines: [], offsetSeconds: 0)

    init(lines: [LyricLine], offsetSeconds: TimeInterval) {
        self.lines = lines
        self.offsetSeconds = offsetSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lines: try container.decode([LyricLine].self, forKey: .lines),
            offsetSeconds: try container.decode(TimeInterval.self, forKey: .offsetSeconds)
        )
    }

    private enum CodingKeys: String, CodingKey { case lines, offsetSeconds }

    // MARK: - Projections

    /// Placed lines (non-nil `time`), sorted ascending by `time`. The timeline,
    /// the HUD, and the lane all consume this.
    var placedLines: [LyricLine] {
        lines.filter { $0.time != nil }.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
    }

    /// Unplaced lines (`nil` `time`), in authoring order. This is the queue.
    var unplacedLines: [LyricLine] {
        lines.filter { $0.time == nil }
    }

    // MARK: - Queries

    /// The media playback time of a *placed* `line` — its song-relative `time`
    /// shifted by the offset, clamped `>= 0`. `nil` for an unplaced line.
    func effectiveTime(of line: LyricLine) -> TimeInterval? {
        line.time.map { max(0, $0 + offsetSeconds) }
    }

    /// The placed line "active" at `mediaSeconds` — the latest whose
    /// `effectiveTime <= mediaSeconds`. `nil` before the first placed line; the
    /// last placed line persists once the playhead is past it.
    func activeLine(atMediaSeconds mediaSeconds: TimeInterval) -> LyricLine? {
        placedLines.last { line in
            (effectiveTime(of: line) ?? .infinity) <= mediaSeconds
        }
    }

    /// The placed line immediately after the one active at `mediaSeconds`; `nil`
    /// once the playhead is past the last placed line.
    func nextLine(afterMediaSeconds mediaSeconds: TimeInterval) -> LyricLine? {
        placedLines.first { line in
            (effectiveTime(of: line) ?? -.infinity) > mediaSeconds
        }
    }

    // MARK: - Transforms (return a copy)

    /// A copy with `lines` replaced (authoring order preserved).
    func settingLines(_ newLines: [LyricLine]) -> Self {
        Self(lines: newLines, offsetSeconds: offsetSeconds)
    }

    /// A copy with the offset replaced.
    func settingOffset(_ newOffset: TimeInterval) -> Self {
        Self(lines: lines, offsetSeconds: newOffset)
    }

    // MARK: - Plain-text parsing

    /// Splits pasted plain text into **unplaced** lyric lines — one row per text
    /// line, blank lines preserved as empty-`text` rows, every row `time = nil`.
    /// CRLF / lone-CR line endings are normalized to LF first (Swift fuses
    /// `\r\n` into one grapheme, so a bare `\n` split misses it).
    static func untimedLines(fromPlainText text: String) -> [LyricLine] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map {
            LyricLine(time: nil, text: String($0))
        }
    }
}
