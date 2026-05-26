import XCTest
@testable import OnlyCue

/// Pins the `File → New from Template…` plumbing: the pending-template hand-off
/// slot (read-and-clear), and that `CueListDocument.init()` picks it up — a new
/// document starts with the template's CuePointType set (with fresh UUIDs), and
/// a plain ⌘N with no pending template gets the canonical 5 default types
/// (General, Lighting, Sound, Scene, Standby — per audit §2.2 / issue #397).
final class NewFromTemplateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TemplateStore.pendingNewDocumentTemplate = nil
    }

    override func tearDown() {
        TemplateStore.pendingNewDocumentTemplate = nil
        super.tearDown()
    }

    private func type(_ name: String) -> CuePointType {
        CuePointType(id: UUID(), name: name, colorHex: "#888888")
    }

    private func isCanonicalDefault(_ types: [CuePointType]) -> Bool {
        types.map(\.name) == ["General", "Lighting", "Sound", "Scene", "Standby"]
    }

    // MARK: - Hand-off slot

    func test_consumePending_returnsThenClears() {
        let template = CueListTemplate(name: "Touring Rig", cuePointTypes: [type("Lighting"), type("Sound")])
        TemplateStore.pendingNewDocumentTemplate = template

        XCTAssertEqual(TemplateStore.consumePendingNewDocumentTemplate(), template)
        XCTAssertNil(TemplateStore.consumePendingNewDocumentTemplate(), "second consume should be empty")
    }

    func test_consumePending_whenEmpty_isNil() {
        XCTAssertNil(TemplateStore.consumePendingNewDocumentTemplate())
    }

    // MARK: - CueListDocument.init() pickup

    func test_newDocument_withoutPendingTemplate_usesTheCanonicalDefaults() {
        XCTAssertTrue(isCanonicalDefault(CueListDocument().model.cuePointTypes))
    }

    func test_newDocument_withPendingTemplate_startsWithTheTemplatesTypes() {
        let lighting = type("Lighting")
        let sound = type("Sound")
        let video = type("Video")
        TemplateStore.pendingNewDocumentTemplate = CueListTemplate(
            name: "Big Show",
            cuePointTypes: [lighting, sound, video]
        )

        let doc = CueListDocument()

        XCTAssertEqual(doc.model.cuePointTypes.map(\.name), ["Lighting", "Sound", "Video"])
        // Fresh UUIDs — not the template file's ids (ADR-015 spirit).
        XCTAssertFalse(doc.model.cuePointTypes.contains { [lighting.id, sound.id, video.id].contains($0.id) })
        // The pending slot was consumed — a subsequent plain new doc is back to the canonical defaults.
        XCTAssertTrue(isCanonicalDefault(CueListDocument().model.cuePointTypes))
    }

    func test_newDocument_withEmptyPendingTemplate_fallsBackToCanonicalDefaults() {
        TemplateStore.pendingNewDocumentTemplate = CueListTemplate(name: "Blank", cuePointTypes: [])
        XCTAssertTrue(isCanonicalDefault(CueListDocument().model.cuePointTypes))
    }
}
