import Foundation

struct ProjectModel: Codable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var name: String
    var media: MediaReference?
    var cues: [Cue]
}
