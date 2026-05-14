import XCTest
@testable import OnlyCue

/// v10 → v11 migration (#244). v10 docs carry a per-item `tempoMap`; v11 lifts
/// tempo onto per-cue `bpm` / `beatsPerBar`. The migration either lands a
/// section's tempo on the nearest existing cue (within one beat) or synthesizes
/// a `"Tempo"` cue at the section's first downbeat.
final class ProjectModelMigrationV11Tests: XCTestCase {

    private static let typeIDString = "AAAA0001-0000-0000-0000-000000000001"
    private var typeID: UUID { UUID(uuidString: Self.typeIDString) ?? UUID() }

    private func cuePointTypesJSON() -> String {
        """
        [{
          "id":"\(Self.typeIDString)","name":"G","colorHex":"#fff",
          "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
          "isVisible":true,"isExportEnabled":true
        }]
        """
    }

    private func wrap(items: String) -> String {
        """
        {
          "schemaVersion": 10,
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": \(cuePointTypesJSON()),
          "items": \(items),
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """
    }

    func test_v10ToV11_singleSectionAlignsWithExistingCue() throws {
        let cueIDString = "BBBB0001-0000-0000-0000-000000000001"
        let cueID = try XCTUnwrap(UUID(uuidString: cueIDString))
        let json = wrap(items: """
        [{
          "id": "22220000-2222-0000-2222-000022220000",
          "media": {"displayName":"x","kind":"audio","duration":60,"bookmarkData":"AQID"},
          "cues": [{
            "id":"\(cueIDString)","typeID":"\(Self.typeIDString)","cueNumber":null,
            "name":"c","time":0.5,"notes":"","fadeTime":{"fadeIn":0,"fadeOut":0}
          }],
          "tempoMap": {"sections":[{
            "id":"33330000-3333-0000-3333-000033330000",
            "startSeconds":0.0,"bpm":120.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.5
          }]},
          "startTimecodeFrames": 0,
          "ltcMuted": false
        }]
        """)

        let migrated = try ProjectModel.decode(from: Data(json.utf8))

        XCTAssertEqual(migrated.schemaVersion, 11)
        XCTAssertEqual(migrated.items[0].cues.count, 1, "no synthetic cue when alignment fits")
        XCTAssertEqual(migrated.items[0].cues[0].id, cueID)
        XCTAssertEqual(migrated.items[0].cues[0].bpm, 120)
        XCTAssertEqual(migrated.items[0].cues[0].beatsPerBar, 4)
    }

    func test_v10ToV11_sectionWithoutNearbyCueInsertsSynthetic() throws {
        let json = wrap(items: """
        [{
          "id": "22220000-2222-0000-2222-000022220000",
          "media": {"displayName":"x","kind":"audio","duration":60,"bookmarkData":"AQID"},
          "cues": [],
          "tempoMap": {"sections":[{
            "id":"33330000-3333-0000-3333-000033330000",
            "startSeconds":0.0,"bpm":100.0,"beatsPerBar":3,"downbeatOffsetSeconds":2.0
          }]},
          "startTimecodeFrames": 0,
          "ltcMuted": false
        }]
        """)

        let migrated = try ProjectModel.decode(from: Data(json.utf8))

        XCTAssertEqual(migrated.items[0].cues.count, 1)
        let synthetic = migrated.items[0].cues[0]
        XCTAssertEqual(synthetic.name, "Tempo")
        XCTAssertEqual(synthetic.time, 2.0, accuracy: 1e-9)
        XCTAssertEqual(synthetic.bpm, 100)
        XCTAssertEqual(synthetic.beatsPerBar, 3)
        XCTAssertEqual(synthetic.typeID, typeID, "uses default cue point type")
        XCTAssertNil(synthetic.cueNumber)
    }

    func test_v10ToV11_emptyTempoMapMigratesCleanly() throws {
        let json = wrap(items: """
        [{
          "id": "22220000-2222-0000-2222-000022220000",
          "media": {"displayName":"x","kind":"audio","duration":60,"bookmarkData":"AQID"},
          "cues": [],
          "tempoMap": {"sections":[]},
          "startTimecodeFrames": 0,
          "ltcMuted": false
        }]
        """)

        let migrated = try ProjectModel.decode(from: Data(json.utf8))
        XCTAssertEqual(migrated.schemaVersion, 11)
        XCTAssertEqual(migrated.items[0].cues.count, 0)
    }

    /// Legacy input with sections in non-monotonic order resolves
    /// deterministically — anchor-time order wins.
    func test_v10ToV11_unsortedSectionsFanOutInTimeOrder() throws {
        let json = wrap(items: """
        [{
          "id": "22220000-2222-0000-2222-000022220000",
          "media": {"displayName":"x","kind":"audio","duration":120,"bookmarkData":"AQID"},
          "cues": [],
          "tempoMap": {"sections":[
            {
              "id":"55550000-5555-0000-5555-000055550000",
              "startSeconds":60.0,"bpm":75.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0
            },
            {
              "id":"33330000-3333-0000-3333-000033330000",
              "startSeconds":0.0,"bpm":120.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0
            }
          ]},
          "startTimecodeFrames": 0,
          "ltcMuted": false
        }]
        """)

        let migrated = try ProjectModel.decode(from: Data(json.utf8))
        let sorted = migrated.items[0].cues.sorted { $0.time < $1.time }
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].time, 0.0, accuracy: 1e-9)
        XCTAssertEqual(sorted[0].bpm, 120)
        XCTAssertEqual(sorted[1].time, 60.0, accuracy: 1e-9)
        XCTAssertEqual(sorted[1].bpm, 75)
    }

    /// Legacy item with no cue-point types: synthetic cues are silently dropped
    /// (no type to assign). Documented behavior — sections that don't land on
    /// an existing cue can't be recovered without a type.
    func test_v10ToV11_emptyCuePointTypes_dropsSyntheticCues() throws {
        let json = """
        {
          "schemaVersion": 10,
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": [],
          "items": [{
            "id": "22220000-2222-0000-2222-000022220000",
            "media": {"displayName":"x","kind":"audio","duration":60,"bookmarkData":"AQID"},
            "cues": [],
            "tempoMap": {"sections":[{
              "id":"33330000-3333-0000-3333-000033330000",
              "startSeconds":5.0,"bpm":120.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0
            }]},
            "startTimecodeFrames": 0,
            "ltcMuted": false
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """

        let migrated = try ProjectModel.decode(from: Data(json.utf8))
        XCTAssertEqual(migrated.schemaVersion, 11)
        XCTAssertEqual(migrated.items[0].cues.count, 0, "no type to assign — synthetic cue is dropped")
    }

    /// Round-trip: a v11 doc encodes and decodes losslessly with tempo on cues.
    func test_v11_serializationRoundTrips() throws {
        let typeID = UUID()
        let cueID = UUID()
        let original = ProjectModel(
            schemaVersion: 11,
            id: UUID(),
            name: "rt",
            cuePointTypes: [CuePointType(id: typeID, name: "G", colorHex: "#fff")],
            items: [MediaItem(
                id: UUID(),
                media: MediaReference(displayName: "x", kind: .audio, duration: 60, bookmarkData: Data()),
                cues: [Cue(
                    id: cueID,
                    typeID: typeID,
                    cueNumber: 1,
                    name: "c",
                    time: 0.5,
                    notes: "",
                    fadeTime: .zero,
                    bpm: 120,
                    beatsPerBar: 4
                )]
            )],
            activeItemID: nil
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try ProjectModel.decode(from: encoded)

        XCTAssertEqual(decoded.items[0].cues[0].bpm, 120)
        XCTAssertEqual(decoded.items[0].cues[0].beatsPerBar, 4)
        XCTAssertEqual(decoded, original)
    }

    /// Out-of-range BPM on disk is clamped through `Cue.init(from:)`.
    func test_v11_decode_clampsOutOfRangeBPM() throws {
        let cueIDString = "BBBB0001-0000-0000-0000-000000000001"
        let json = """
        {
          "schemaVersion": 11,
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "rt",
          "cuePointTypes": \(cuePointTypesJSON()),
          "items": [{
            "id": "22220000-2222-0000-2222-000022220000",
            "media": {"displayName":"x","kind":"audio","duration":60,"bookmarkData":"AQID"},
            "cues": [{
              "id":"\(cueIDString)","typeID":"\(Self.typeIDString)","cueNumber":null,
              "name":"c","time":0,"notes":"","fadeTime":{"fadeIn":0,"fadeOut":0},
              "bpm": 9999, "beatsPerBar": 99
            }],
            "startTimecodeFrames": 0,
            "ltcMuted": false
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """

        let migrated = try ProjectModel.decode(from: Data(json.utf8))
        XCTAssertEqual(migrated.items[0].cues[0].bpm, 400)
        XCTAssertEqual(migrated.items[0].cues[0].beatsPerBar, 16)
    }

    func test_v10ToV11_multipleSectionsFanOut() throws {
        let cueIDString = "BBBB0001-0000-0000-0000-000000000001"
        let cueID = try XCTUnwrap(UUID(uuidString: cueIDString))
        let json = wrap(items: """
        [{
          "id": "22220000-2222-0000-2222-000022220000",
          "media": {"displayName":"x","kind":"audio","duration":60,"bookmarkData":"AQID"},
          "cues": [{
            "id":"\(cueIDString)","typeID":"\(Self.typeIDString)","cueNumber":null,
            "name":"c","time":0.0,"notes":"","fadeTime":{"fadeIn":0,"fadeOut":0}
          }],
          "tempoMap": {"sections":[
            {
              "id":"33330000-3333-0000-3333-000033330000",
              "startSeconds":0.0,"bpm":120.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0
            },
            {
              "id":"44440000-4444-0000-4444-000044440000",
              "startSeconds":30.0,"bpm":75.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0
            }
          ]},
          "startTimecodeFrames": 0,
          "ltcMuted": false
        }]
        """)

        let migrated = try ProjectModel.decode(from: Data(json.utf8))

        XCTAssertEqual(migrated.items[0].cues.count, 2, "existing + synthetic for second section")
        let sorted = migrated.items[0].cues.sorted { $0.time < $1.time }
        XCTAssertEqual(sorted[0].id, cueID)
        XCTAssertEqual(sorted[0].bpm, 120)
        XCTAssertEqual(sorted[1].time, 30.0, accuracy: 1e-9)
        XCTAssertEqual(sorted[1].bpm, 75)
        XCTAssertEqual(sorted[1].name, "Tempo")
    }
}
