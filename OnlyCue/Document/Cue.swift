import Foundation

struct Cue: Codable, Identifiable, Equatable {
    var id: UUID
    var typeID: UUID
    var cueNumber: Double
    var name: String
    var time: TimeInterval
    var notes: String
    var fadeTime: FadeTime
}
