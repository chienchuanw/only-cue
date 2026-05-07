import Foundation

struct Cue: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var time: TimeInterval
    var colorHex: String
    var notes: String
}
