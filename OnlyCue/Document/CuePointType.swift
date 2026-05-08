import Foundation

struct CuePointType: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String
    var defaultFadeTime: TimeInterval
    var defaultNamePattern: String
    var hotkey: Int?
    var isVisible: Bool
    var isExportEnabled: Bool

    init(
        id: UUID,
        name: String,
        colorHex: String,
        defaultFadeTime: TimeInterval = 0,
        defaultNamePattern: String = "Cue",
        hotkey: Int? = nil,
        isVisible: Bool = true,
        isExportEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.defaultFadeTime = defaultFadeTime
        self.defaultNamePattern = defaultNamePattern
        self.hotkey = hotkey
        self.isVisible = isVisible
        self.isExportEnabled = isExportEnabled
    }
}
