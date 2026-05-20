import Foundation

/// A single timestamped lyric line. `time` is SONG-relative seconds — measured
/// from where the song begins, not from the media file's start (see `Lyrics`).
/// `text` may be empty; an empty line marks an instrumental gap in the HUD.
struct LyricLine: Codable, Identifiable, Equatable {
    var id: UUID
    var time: TimeInterval
    var text: String

    init(id: UUID = UUID(), time: TimeInterval, text: String) {
        self.id = id
        self.time = max(0, time)
        self.text = text
    }

    /// Route decode through the clamping init so a hand-edited negative `time`
    /// on disk is normalized rather than silently accepted (mirrors `Cue`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            time: try container.decode(TimeInterval.self, forKey: .time),
            text: try container.decode(String.self, forKey: .text)
        )
    }

    private enum CodingKeys: String, CodingKey { case id, time, text }
}
