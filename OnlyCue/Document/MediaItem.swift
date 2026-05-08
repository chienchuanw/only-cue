import Foundation

struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference
    var cues: [Cue]
}
