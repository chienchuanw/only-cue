import Foundation

/// v10 → v11 migration: tempo moves from `MediaItem.tempoMap` onto cues.
///
/// Strategy per item: for each tempo section, find the cue whose time is closest to
/// `startSeconds + downbeatOffsetSeconds` within a one-beat tolerance (`60 / bpm`). If
/// found, copy the section's `bpm`/`beatsPerBar` onto it. If not found, insert a
/// synthetic cue named "Tempo" at the section's first downbeat carrying the tempo.
/// The `tempoMap` field is dropped.
///
/// The migration uses a private decode-only copy of the v10 tempo shape so the live
/// `TempoMap` / `TempoSection` types can be deleted in Leaf 5 without disturbing
/// historical migrations.
extension ProjectModel {

    static func migrateFromV10(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV10.self, from: data)
        let defaultTypeID = legacy.cuePointTypes.first?.id
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem(defaultTypeID: defaultTypeID) },
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings
        )
    }

    /// Fan a list of legacy tempo sections onto a list of cues. Used by every
    /// migration whose source schema carried `MediaItem.tempoMap` (v8, v9, v10).
    /// Each section either lands its BPM on the nearest existing cue (within
    /// one beat) or appears as a new synthetic "Tempo" cue at its first
    /// downbeat. Returns the resulting cues sorted by time.
    static func applyLegacyTempoSectionsToCues(
        _ sections: [LegacyTempoSection],
        cues: [Cue],
        defaultTypeID: UUID?
    ) -> [Cue] {
        var working = cues
        for section in sections {
            let anchor = section.startSeconds + section.downbeatOffsetSeconds
            let tolerance = 60.0 / max(section.bpm, 1)
            if let index = nearestCueIndex(in: working, to: anchor, within: tolerance) {
                working[index].bpm = section.bpm
                working[index].beatsPerBar = section.beatsPerBar
            } else if let typeID = defaultTypeID {
                working.append(Cue(
                    id: UUID(),
                    typeID: typeID,
                    cueNumber: nil,
                    name: "Tempo",
                    time: anchor,
                    notes: "",
                    fadeTime: .zero,
                    bpm: section.bpm,
                    beatsPerBar: section.beatsPerBar
                ))
            }
        }
        return working.sorted { $0.time < $1.time }
    }

    private static func nearestCueIndex(in cues: [Cue], to time: TimeInterval, within tolerance: TimeInterval) -> Int? {
        var bestIndex: Int?
        var bestDelta = Double.infinity
        for (index, cue) in cues.enumerated() {
            let delta = abs(cue.time - time)
            if delta <= tolerance && delta < bestDelta {
                bestIndex = index
                bestDelta = delta
            }
        }
        return bestIndex
    }

    // MARK: - Legacy v10 decode shapes

    private struct LegacyV10: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV10Item]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
    }

    private struct LegacyV10Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [Cue]
        let tempoMap: LegacyTempoMap
        let startTimecodeFrames: Int
        let ltcMuted: Bool

        func toMediaItem(defaultTypeID: UUID?) -> MediaItem {
            let migratedCues = ProjectModel.applyLegacyTempoSectionsToCues(
                tempoMap.sections,
                cues: cues,
                defaultTypeID: defaultTypeID
            )
            return MediaItem(
                id: id,
                media: media,
                cues: migratedCues,
                startTimecodeFrames: startTimecodeFrames,
                ltcMuted: ltcMuted
            )
        }
    }

    struct LegacyTempoMap: Decodable {
        let sections: [LegacyTempoSection]
    }

    struct LegacyTempoSection: Decodable {
        let id: UUID
        let startSeconds: TimeInterval
        let bpm: Double
        let beatsPerBar: Int
        let downbeatOffsetSeconds: TimeInterval
    }
}
