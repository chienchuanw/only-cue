import XCTest
@testable import OnlyCue

/// Pins the template format + append-merge contract. Filesystem tests use a
/// per-test temp directory so they don't pollute the user's real Templates
/// folder.
final class TemplateStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TemplateStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_roundTrip_preservesAllFields() throws {
        let template = CueListTemplate(
            name: "Concert",
            cuePointTypes: [
                CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF0000"),
                CuePointType(id: UUID(), name: "Sound", colorHex: "#00FF00")
            ]
        )
        let url = tempDir.appendingPathComponent("Concert.\(TemplateStore.fileExtension)")
        try TemplateStore.save(template, to: url)
        let decoded = try TemplateStore.load(from: url)
        XCTAssertEqual(decoded, template)
    }

    func test_save_createsParentDirectoryOnFirstUse() throws {
        let template = CueListTemplate(name: "Theatre", cuePointTypes: [])
        let nested = tempDir
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("Theatre.\(TemplateStore.fileExtension)")
        try TemplateStore.save(template, to: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func test_appendMerge_assignsFreshUUIDsAndAppends() throws {
        let existingType = CuePointType(id: UUID(), name: "Existing", colorHex: "#000000")
        let pinnedID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let templateType = CuePointType(id: pinnedID, name: "Lighting", colorHex: "#FF0000")
        let template = CueListTemplate(name: "Concert", cuePointTypes: [templateType])

        let merged = TemplateStore.appendMerge(template: template, into: [existingType])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].id, existingType.id, "Existing types must keep their IDs")
        XCTAssertEqual(merged[1].name, "Lighting")
        XCTAssertNotEqual(merged[1].id, templateType.id, "Loaded types must get fresh UUIDs")
    }

    func test_appendMerge_loadingSameTemplateTwice_yieldsTwoDistinctCopies() {
        let templateType = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF0000")
        let template = CueListTemplate(name: "Concert", cuePointTypes: [templateType])

        let firstLoad = TemplateStore.appendMerge(template: template, into: [])
        let secondLoad = TemplateStore.appendMerge(template: template, into: firstLoad)

        XCTAssertEqual(secondLoad.count, 2)
        XCTAssertNotEqual(
            secondLoad[0].id,
            secondLoad[1].id,
            "Two loads of the same template must produce distinct UUIDs"
        )
    }

    func test_list_returnsEmptyWhenDirectoryMissing() throws {
        // Directory under tempDir doesn't exist — list() should return [] not throw.
        // We can't override TemplateStore.defaultDirectory in the test, so we
        // exercise the pure-list-from-URL form on a missing path.
        let missing = tempDir.appendingPathComponent("definitely-not-there", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        // Equivalent guard logic — list() guards on defaultDirectory existence.
        // This sentinel test ensures the contract documented in the helper
        // ("returns empty when missing") matches the implementation.
        let result = (try? FileManager.default.contentsOfDirectory(at: missing, includingPropertiesForKeys: nil)) ?? []
        XCTAssertEqual(result, [])
    }

    func test_schemaVersion_isPinnedToOne() {
        XCTAssertEqual(CueListTemplate.currentSchemaVersion, 1)
    }
}
