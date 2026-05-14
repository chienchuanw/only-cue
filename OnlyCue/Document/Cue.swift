import Foundation

struct Cue: Codable, Identifiable, Equatable {
    var id: UUID
    var typeID: UUID
    var cueNumber: Double?
    var name: String
    var time: TimeInterval
    var notes: String
    var fadeTime: FadeTime
    var bpm: Double?
    var beatsPerBar: Int?

    init(
        id: UUID,
        typeID: UUID,
        cueNumber: Double?,
        name: String,
        time: TimeInterval,
        notes: String,
        fadeTime: FadeTime,
        bpm: Double? = nil,
        beatsPerBar: Int? = nil
    ) {
        self.id = id
        self.typeID = typeID
        self.cueNumber = cueNumber
        self.name = name
        self.time = time
        self.notes = notes
        self.fadeTime = fadeTime
        self.bpm = bpm.map { min(max($0, 20), 400) }
        self.beatsPerBar = beatsPerBar.map { max(1, min($0, 16)) }
    }
}
