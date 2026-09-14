import Foundation
@testable import OnlyCue

// Shared contract model for the two grandMA2 golden vectors (epic #728, M1c —
// vectors 4 and 5). Both describe the same inputs, so the cue and target shapes
// live here rather than being spelled twice and drifting apart.
//
// See `MA2TelnetGoldenVectorTests` (vector 4, the telnet command list) and
// `MA2ExportGoldenVectorTests` (vector 5, the four export artifacts).

struct MA2TelnetGoldenVector: Codable, Equatable {
    let contract: String   // "ma2-telnet"
    let version: Int       // 1
    let note: String
    let plans: [PlanCase]
    let trigTimes: [TrigTimeCase]
    let cueNumbers: [CueNumberCase]
    let names: [NameCase]

    /// Only the fields `MA2CommandPlanner` reads. Cues are identified by
    /// position, so the vector mints no UUIDs.
    struct CueInput: Codable, Equatable {
        let cueNumber: GoldenDouble?
        let name: String
        let time: GoldenDouble
        let notes: String
        let fadeIn: GoldenDouble
        let fadeOut: GoldenDouble
    }

    /// `MA2PushTarget`'s command-relevant fields. `executorPage` / `executorNumber`
    /// are nil together when the sequence is left unassigned (#764).
    struct TargetInput: Codable, Equatable {
        let sequenceSlot: Int
        let timecodeSlot: Int
        let executorPage: Int?
        let executorNumber: Int?
        let timecodeCommand: String
    }

    struct PlanCase: Codable, Equatable {
        let name: String
        let cues: [CueInput]
        let target: TargetInput
        let sequenceName: String
        let startTimecodeFrames: Int
        let framerate: String
        let expect: [String]
    }

    struct TrigTimeCase: Codable, Equatable {
        let name: String
        let cueTime: GoldenDouble
        let startTimecodeFrames: Int
        let framerate: String
        let expectSeconds: GoldenDouble
        let expectCommand: String
    }

    struct CueNumberCase: Codable, Equatable {
        let name: String
        let value: GoldenDouble
        let expectNumber: Int
        let expectSubNumber: Int
        let expectCommandString: String
    }

    struct NameCase: Codable, Equatable {
        let name: String
        let raw: String
        let fallbackSlot: Int
        let expect: String
    }
}

// MARK: - Input builders (shared by both generators)

enum MA2GoldenInput {

    /// Deterministic, total and collision-free at these case sizes, so the
    /// vector's index mapping is reproducible without minting random UUIDs.
    private static func identifier(_ index: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index >> 8), UInt8(index & 0xFF)))
    }

    /// Positional on purpose: a case list reads as a cue sheet, and the labels that
    /// do survive (`at:`, `fadeIn:`) are the ones a reader would otherwise guess at.
    static func cue(
        _ number: Double?,
        _ name: String,
        at time: Double,
        notes: String = "",
        fadeIn: Double = 0,
        fadeOut: Double = 0
    ) -> MA2TelnetGoldenVector.CueInput {
        .init(
            cueNumber: GoldenDouble(number),
            name: name,
            time: GoldenDouble(time),
            notes: notes,
            fadeIn: GoldenDouble(fadeIn),
            fadeOut: GoldenDouble(fadeOut)
        )
    }

    static func cues(_ inputs: [MA2TelnetGoldenVector.CueInput]) -> [Cue] {
        inputs.enumerated().map { index, entry in
            Cue(
                id: identifier(index),
                typeID: identifier(0),
                cueNumber: entry.cueNumber?.value,
                name: entry.name,
                time: entry.time.value,
                notes: entry.notes,
                fadeTime: FadeTime(fadeIn: entry.fadeIn.value, fadeOut: entry.fadeOut.value)
            )
        }
    }

    static func target(_ input: MA2TelnetGoldenVector.TargetInput) -> MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: input.sequenceSlot,
            timecodeSlot: input.timecodeSlot,
            executorPage: input.executorPage,
            executorNumber: input.executorNumber,
            // The token is the persisted lowercase raw value. `MA2CommandPlanner`
            // never reads it, so the fallback only matters to vector 5's reader.
            timecodeCommand: MA2TimecodeCommand(rawValue: input.timecodeCommand) ?? .goto,
            includedTypeIDs: []
        )
    }

}
