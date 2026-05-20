import Foundation

/// A single lyric line. `time` is SONG-relative seconds (measured from where the
/// song begins, not the media file's start — see `Lyrics`); `nil` means the line
/// is *unplaced* — it has text but no timestamp yet and waits in the authoring
/// queue. `text` may be empty; an empty placed line marks an instrumental gap.
struct LyricLine: Codable, Identifiable, Equatable {
    var id: UUID
    var time: TimeInterval?
    var text: String

    init(id: UUID = UUID(), time: TimeInterval?, text: String) {
        self.id = id
        self.time = time.map { max(0, $0) }
        self.text = text
    }

    /// Route decode through the clamping init. `time` is decoded leniently — a
    /// v13 document always wrote a concrete value; a v14 unplaced line omits the
    /// key entirely (synthesized `encode` uses `encodeIfPresent` for optionals).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            time: try container.decodeIfPresent(TimeInterval.self, forKey: .time),
            text: try container.decode(String.self, forKey: .text)
        )
    }

    private enum CodingKeys: String, CodingKey { case id, time, text }
}
