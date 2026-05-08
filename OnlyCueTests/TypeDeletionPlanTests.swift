import XCTest
@testable import OnlyCue

final class TypeDeletionPlanTests: XCTestCase {

    func test_plan_returnsNil_whenOnlyOneTypeRemains() {
        let general = CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4")
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [general],
            items: [],
            activeItemID: nil
        )

        XCTAssertNil(
            TypeDeletionPlan.make(forTypeID: general.id, in: model),
            "cannot delete the last Type"
        )
    }

    func test_plan_countsReferencedCues_acrossItems() throws {
        let general = CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4")
        let lighting = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF6B6B")
        let cue = { (typeID: UUID, time: TimeInterval) in
            Cue(id: UUID(), typeID: typeID, cueNumber: 1, name: "C", time: time, notes: "", fadeTime: .zero)
        }
        let item1 = MediaItem(
            id: UUID(),
            media: makeMedia(),
            cues: [cue(lighting.id, 1), cue(general.id, 2), cue(lighting.id, 3)]
        )
        let item2 = MediaItem(
            id: UUID(),
            media: makeMedia(),
            cues: [cue(lighting.id, 1)]
        )
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [general, lighting],
            items: [item1, item2],
            activeItemID: item1.id
        )

        let plan = try XCTUnwrap(TypeDeletionPlan.make(forTypeID: lighting.id, in: model))
        XCTAssertEqual(plan.typeID, lighting.id)
        XCTAssertEqual(plan.typeName, "Lighting")
        XCTAssertEqual(plan.referencedCueCount, 3, "two in item1 plus one in item2")
        XCTAssertEqual(plan.reassignTargetID, general.id)
        XCTAssertEqual(plan.reassignTargetName, "General")
    }

    func test_plan_targetsCuePointTypesIndexOne_whenDeletingDefault() throws {
        let general = CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4")
        let lighting = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF6B6B")
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [general, lighting],
            items: [],
            activeItemID: nil
        )

        let plan = try XCTUnwrap(TypeDeletionPlan.make(forTypeID: general.id, in: model))
        XCTAssertEqual(
            plan.reassignTargetID,
            lighting.id,
            "deleting the default Type reassigns to cuePointTypes[1]"
        )
    }

    func test_plan_zeroCueCount_whenTypeUnreferenced() throws {
        let general = CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4")
        let unused = CuePointType(id: UUID(), name: "Unused", colorHex: "#FF0000")
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [general, unused],
            items: [],
            activeItemID: nil
        )

        let plan = try XCTUnwrap(TypeDeletionPlan.make(forTypeID: unused.id, in: model))
        XCTAssertEqual(plan.referencedCueCount, 0)
    }

    private func makeMedia() -> MediaReference {
        MediaReference(displayName: "x.wav", kind: .audio, duration: 60, bookmarkData: Data([0x00]))
    }
}
