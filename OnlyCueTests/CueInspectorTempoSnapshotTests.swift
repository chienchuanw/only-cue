import SwiftUI
import XCTest
@testable import OnlyCue

/// Visual baselines for the cue inspector's Tempo group (#252, follow-up to
/// #246). Two states: a selected cue with no BPM (placeholder visible) and a
/// selected cue with BPM 120 / 4 per bar. Each test renders the view via
/// SwiftUI `ImageRenderer` (no XCUITest harness needed) and attaches the PNG
/// to the test result so a developer can diff the baselines locally.
@MainActor
final class CueInspectorTempoSnapshotTests: XCTestCase {

    func test_inspector_withoutBPM_renders() throws {
        let doc = makeDoc(bpm: nil, beatsPerBar: nil)
        let image = try render(inspector(for: doc))
        attach(image, name: "inspector-tempo-empty")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func test_inspector_withBPM_renders() throws {
        let doc = makeDoc(bpm: 120, beatsPerBar: 4)
        let image = try render(inspector(for: doc))
        attach(image, name: "inspector-tempo-set")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    // MARK: - Helpers

    private func inspector(for doc: CueListDocument) -> some View {
        CueInspectorView(document: doc, cue: doc.model.items.first?.cues.first)
            .frame(width: 280, height: 360)
    }

    private func makeDoc(bpm: Double?, beatsPerBar: Int?) -> CueListDocument {
        let typeID = UUID()
        let doc = CueListDocument()
        doc.model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "snap",
            cuePointTypes: [CuePointType(id: typeID, name: "General", colorHex: "#4ECDC4")],
            items: [MediaItem(
                id: UUID(),
                media: MediaReference(displayName: "song.wav", kind: .audio, duration: 60, bookmarkData: Data()),
                cues: [Cue(
                    id: UUID(),
                    typeID: typeID,
                    cueNumber: 1.0,
                    name: "Cue 1",
                    time: 0,
                    notes: "",
                    fadeTime: .zero,
                    bpm: bpm,
                    beatsPerBar: beatsPerBar
                )]
            )]
        )
        doc.model.activeItemID = doc.model.items.first?.id
        return doc
    }

    private func render<V: View>(_ view: V) throws -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            throw XCTSkip("ImageRenderer returned nil — likely missing AppKit context in this run")
        }
        return image
    }

    private func attach(_ image: NSImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
