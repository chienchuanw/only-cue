import XCTest
@testable import OnlyCue

/// Layout-fidelity coverage for `TimelineBreakdownLayout` beyond the basic
/// cases in `TimelineBreakdownLayoutTests` — large Type counts, model order
/// never re-sorted, all-hidden, the default-shaped project (one Type, no
/// cues — the post-v1/v2-migration state), and the layout run against a v3
/// `.cuelist` decoded + migrated to the current schema. Closes epic #37.
final class TimelineBreakdownLayoutFidelityTests: XCTestCase {

    private func type(_ name: String, visible: Bool = true) -> CuePointType {
        CuePointType(id: UUID(), name: name, colorHex: "#888888", isVisible: visible)
    }

    private func cue(_ typeID: UUID, time: TimeInterval) -> Cue {
        Cue(id: UUID(), typeID: typeID, cueNumber: 0, name: "C", time: time, notes: "", fadeTime: .zero)
    }

    func test_manyTypes_eachGetsOneLaneInModelOrder() {
        let names = (0..<30).map { String(format: "T%02d", $0) }
        let types = names.map { type($0) }
        let lanes = TimelineBreakdownLayout.lanes(cues: [], types: types)
        XCTAssertEqual(lanes.count, 30)
        XCTAssertEqual(lanes.map(\.name), names)
    }

    func test_largeCueSetAcrossManyLanes_isPartitionedExactly() {
        let types = (0..<10).map { type("T\($0)") }
        var cues: [Cue] = []
        for laneType in types {
            cues += (0..<50).map { cue(laneType.id, time: TimeInterval($0)) }
        }
        cues += (0..<25).map { _ in cue(UUID(), time: 1) }   // stray-typed — dropped

        let lanes = TimelineBreakdownLayout.lanes(cues: cues, types: types)
        XCTAssertEqual(lanes.count, 10)
        XCTAssertTrue(lanes.allSatisfy { $0.cues.count == 50 })
        XCTAssertEqual(lanes.reduce(0) { $0 + $1.cues.count }, 500)
        for laneType in types {
            XCTAssertTrue(lanes.first { $0.typeID == laneType.id }?.cues.allSatisfy { $0.typeID == laneType.id } ?? false)
        }
    }

    func test_allTypesHidden_yieldsNoLanes_butHiddenCountIsTheTotal() {
        let types = (0..<8).map { type("T\($0)", visible: false) }
        XCTAssertTrue(TimelineBreakdownLayout.lanes(cues: [], types: types).isEmpty)
        XCTAssertEqual(TimelineBreakdownLayout.hiddenCount(types: types), 8)
    }

    func test_partialVisibility_keepsVisibleLanesInOriginalRelativeOrder() {
        // Hide indices 1, 3, 5 of T0…T5 → lanes are T0, T2, T4 in that order.
        let types = (0..<6).map { type("T\($0)", visible: $0 % 2 == 0) }
        let lanes = TimelineBreakdownLayout.lanes(cues: [], types: types)
        XCTAssertEqual(lanes.map(\.name), ["T0", "T2", "T4"])
        XCTAssertEqual(TimelineBreakdownLayout.hiddenCount(types: types), 3)
    }

    func test_defaultProjectShape_oneTypeNoCues_yieldsOneEmptyLane() {
        let lanes = TimelineBreakdownLayout.lanes(cues: [], types: [ProjectModel.makeDefaultCuePointType()])
        XCTAssertEqual(lanes.count, 1)
        XCTAssertEqual(lanes.first?.cues, [])
        XCTAssertEqual(lanes.first?.name, ProjectModel.makeDefaultCuePointType().name)
    }

    func test_laneOrderNeverSorted_followsModelOrderEvenWhenNamesReverseSorted() {
        let lanes = TimelineBreakdownLayout.lanes(cues: [], types: [type("Z"), type("M"), type("A")])
        XCTAssertEqual(lanes.map(\.name), ["Z", "M", "A"])
    }

    func test_layoutOnMigratedV3Document_isCorrect() throws {
        let data = try XCTUnwrap(Self.v3FixtureJSON.data(using: .utf8))
        let model = try ProjectModel.decode(from: data)
        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion, "decode should migrate to the current schema")

        let item = try XCTUnwrap(model.activeItem)
        let lanes = TimelineBreakdownLayout.lanes(cues: item.cues, types: model.cuePointTypes)

        XCTAssertEqual(lanes.map(\.name), ["General"])
        XCTAssertEqual(Set(lanes[0].cues.map(\.time)), [5, 15, 30])
        XCTAssertTrue(lanes[0].cues.allSatisfy { $0.typeID == model.cuePointTypes[0].id })
    }

    private static let v3FixtureJSON = """
    {
      "schemaVersion": 3,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
      "name": "Show",
      "cuePointTypes": [
        {
          "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "General",
          "colorHex": "#4ECDC4",
          "defaultFadeTime": 0,
          "defaultNamePattern": "Cue",
          "isVisible": true,
          "isExportEnabled": true
        }
      ],
      "items": [
        {
          "id": "AABBCCDD-1111-2222-3333-444455556666",
          "media": {
            "displayName": "act1.wav",
            "kind": "audio",
            "duration": 100,
            "bookmarkData": "AQID"
          },
          "cues": [
            { "id": "11111111-1111-1111-1111-111111111111", "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "name": "C", "time": 30.0, "colorHex": "#FF6B6B", "notes": "" },
            { "id": "22222222-2222-2222-2222-222222222222", "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "name": "A", "time": 5.0, "colorHex": "#4ECDC4", "notes": "" },
            { "id": "33333333-3333-3333-3333-333333333333", "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
              "name": "B", "time": 15.0, "colorHex": "#4ECDC4", "notes": "" }
          ]
        }
      ],
      "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
    }
    """
}
