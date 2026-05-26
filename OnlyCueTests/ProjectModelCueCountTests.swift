import XCTest
@testable import OnlyCue

/// Pins `ProjectModel.cueCount(forTypeID:)` — the helper that backs the
/// Manage Types row count badge (audit §10.1 / #418).
final class ProjectModelCueCountTests: XCTestCase {

    func test_countsCuesAcrossEveryItem() throws {
        let lighting = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FFD93D")
        let sound = CuePointType(id: UUID(), name: "Sound", colorHex: "#4D96FF")
        let media = MediaReference(displayName: "a.wav", kind: .audio, duration: 10, bookmarkData: Data())
        let cueA = Cue(id: UUID(), typeID: lighting.id, cueNumber: 1, name: "", time: 0, notes: "", fadeTime: .zero)
        let cueB = Cue(id: UUID(), typeID: lighting.id, cueNumber: 2, name: "", time: 1, notes: "", fadeTime: .zero)
        let cueC = Cue(id: UUID(), typeID: sound.id, cueNumber: 3, name: "", time: 2, notes: "", fadeTime: .zero)
        let item1 = MediaItem(id: UUID(), media: media, cues: [cueA])
        let item2 = MediaItem(id: UUID(), media: media, cues: [cueB, cueC])
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [lighting, sound],
            items: [item1, item2],
            activeItemID: item1.id
        )

        XCTAssertEqual(model.cueCount(forTypeID: lighting.id), 2)
        XCTAssertEqual(model.cueCount(forTypeID: sound.id), 1)
    }

    func test_returnsZeroForUnusedType() throws {
        let general = CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4")
        let unused = CuePointType(id: UUID(), name: "Standby", colorHex: "#FFA94D")
        let media = MediaReference(displayName: "a.wav", kind: .audio, duration: 10, bookmarkData: Data())
        let cue = Cue(id: UUID(), typeID: general.id, cueNumber: 1, name: "", time: 0, notes: "", fadeTime: .zero)
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [general, unused],
            items: [MediaItem(id: UUID(), media: media, cues: [cue])],
            activeItemID: nil
        )

        XCTAssertEqual(model.cueCount(forTypeID: unused.id), 0)
    }
}
