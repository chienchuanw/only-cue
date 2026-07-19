import XCTest
@testable import OnlyCue

/// #686 — v17 → v18 migration: `MA2PushTarget` gains optional `sequenceName`.
/// A v17 document must still load under the current (v18) schema.
final class ProjectModelMigrationV18Tests: XCTestCase {
    func test_v17Document_loadsAndReStampsCurrentSchema() throws {
        // Stamp a well-shaped document as v17 via the real init, so timecodeSettings
        // / playbackMode encode in their exact on-disk shape.
        let model = ProjectModel(
            schemaVersion: 17,
            id: UUID(),
            name: "P",
            cuePointTypes: [],
            items: [],
            activeItemID: nil
        )
        let data = try JSONEncoder().encode(model)

        let migrated = try ProjectModel.decode(from: data)

        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
    }
}
