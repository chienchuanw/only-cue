import Foundation

enum MediaKind: String, Codable {
    case audio
    case video
}

struct MediaReference: Codable, Equatable {
    var displayName: String
    var kind: MediaKind
    var duration: TimeInterval
    var bookmarkData: Data
}
