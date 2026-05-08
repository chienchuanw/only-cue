import Foundation

struct CuePointType: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String
    var defaultFadeTime: TimeInterval = 0
    var defaultNamePattern: String = "Cue"
    var hotkey: Int?
    var isVisible: Bool = true
    var isExportEnabled: Bool = true
}
