import Foundation

/// Pure layout for the timeline breakdown view: turns the project's cues +
/// CuePointTypes into one lane per *visible* Type, each lane carrying that
/// Type's cues. Lane order follows the model's Type order (insertion order —
/// no reordering in v1). Marker x positions within a lane reuse
/// `CueMarkersGeometry.position`, the same time→x mapping the waveform overlay
/// uses, so a cue lands at the same horizontal spot in either view.
enum TimelineBreakdownLayout {

    struct Lane: Identifiable, Equatable {
        let typeID: UUID
        let name: String
        let colorHex: String
        let cues: [Cue]

        var id: UUID { typeID }
    }

    /// One lane per visible Type, in model order. A Type with no cues still
    /// gets a (empty) lane so the category is visible. Cues whose `typeID`
    /// matches no Type are dropped — that shouldn't happen (`removeCuePointType`
    /// reassigns referencing cues), but a stray one silently vanishing beats a
    /// phantom lane.
    static func lanes(cues: [Cue], types: [CuePointType]) -> [Lane] {
        types
            .filter(\.isVisible)
            .map { type in
                Lane(
                    typeID: type.id,
                    name: type.name,
                    colorHex: type.colorHex,
                    cues: cues.filter { $0.typeID == type.id }
                )
            }
    }

    /// How many Type lanes are currently hidden — drives the "+N hidden"
    /// affordance.
    static func hiddenCount(types: [CuePointType]) -> Int {
        types.filter { !$0.isVisible }.count
    }
}
