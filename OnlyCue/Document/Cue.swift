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
        // NaN / infinity defeats min/max clamping; drop to nil rather than
        // accept a value that would propagate through every grid computation.
        if let bpm, bpm.isFinite {
            self.bpm = min(max(bpm, 20), 400)
        } else {
            self.bpm = nil
        }
        self.beatsPerBar = beatsPerBar.map { max(1, min($0, 16)) }
    }

    /// Route every decode through the clamping init so an out-of-range
    /// `bpm`/`beatsPerBar` on disk (hand-edited document, future-format leak)
    /// is normalized rather than silently accepted.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            typeID: try container.decode(UUID.self, forKey: .typeID),
            cueNumber: try container.decodeIfPresent(Double.self, forKey: .cueNumber),
            name: try container.decode(String.self, forKey: .name),
            time: try container.decode(TimeInterval.self, forKey: .time),
            notes: try container.decode(String.self, forKey: .notes),
            fadeTime: try container.decode(FadeTime.self, forKey: .fadeTime),
            bpm: try container.decodeIfPresent(Double.self, forKey: .bpm),
            beatsPerBar: try container.decodeIfPresent(Int.self, forKey: .beatsPerBar)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, typeID, cueNumber, name, time, notes, fadeTime, bpm, beatsPerBar
    }
}
