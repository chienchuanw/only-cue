import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsTransferTests: XCTestCase {

    // MARK: fixtures

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func makeItem(name: String, cues: [Cue]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 100,
                bookmarkData: Data([0x00])
            ),
            cues: cues
        )
    }

    private func cue(typeID: UUID, time: TimeInterval) -> Cue {
        Cue(
            id: UUID(),
            typeID: typeID,
            cueNumber: 1,
            name: "c",
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    /// A document with one active item that has no cues.
    private func documentWithEmptyActiveItem() -> CueListDocument {
        let doc = CueListDocument()
        let item = makeItem(name: "song.wav", cues: [])
        CueCommands.addItem(item, to: doc, undoManager: nil)
        return doc
    }

    private func export(typeName: String, cueTimes: [TimeInterval]) -> CueListExport {
        let typeID = UUID()
        return CueListExport(
            formatVersion: CueListTransfer.currentFormatVersion,
            exportedAt: Date(),
            sourceMedia: ExportedSourceMedia(displayName: "song.wav", duration: 100),
            cuePointTypes: [CuePointType(id: typeID, name: typeName, colorHex: "#FFFFFF")],
            cues: cueTimes.map { cue(typeID: typeID, time: $0) }
        )
    }

    // MARK: tests

    func test_importCueList_replace_setsCuesAndAddsType() throws {
        let doc = documentWithEmptyActiveItem()
        let typesBefore = doc.model.cuePointTypes.count

        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1, 2, 3]),
            mode: .replace,
            document: doc,
            undoManager: nil
        )

        XCTAssertEqual(doc.model.items[0].cues.map(\.time), [1, 2, 3])
        XCTAssertEqual(doc.model.cuePointTypes.count, typesBefore + 1)
        let newTypeID = try XCTUnwrap(doc.model.cuePointTypes.last).id
        XCTAssertTrue(doc.model.items[0].cues.allSatisfy { $0.typeID == newTypeID })
    }

    func test_importCueList_add_appendsToExistingCues() {
        let doc = CueListDocument()
        let existingType = doc.model.cuePointTypes[0].id
        let item = makeItem(name: "song.wav", cues: [cue(typeID: existingType, time: 9)])
        CueCommands.addItem(item, to: doc, undoManager: nil)

        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1, 2]),
            mode: .add,
            document: doc,
            undoManager: nil
        )

        XCTAssertEqual(doc.model.items[0].cues.map(\.time), [9, 1, 2])
    }

    func test_importCueList_undo_restoresCuesAndTypes() {
        let doc = documentWithEmptyActiveItem()
        let typesBefore = doc.model.cuePointTypes
        let undo = makeUndoManager()

        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1, 2, 3]),
            mode: .replace,
            document: doc,
            undoManager: undo
        )
        XCTAssertEqual(doc.model.items[0].cues.count, 3)

        undo.undo()
        XCTAssertTrue(doc.model.items[0].cues.isEmpty)
        XCTAssertEqual(doc.model.cuePointTypes, typesBefore)

        undo.redo()
        XCTAssertEqual(doc.model.items[0].cues.count, 3)
        XCTAssertEqual(doc.model.cuePointTypes.count, typesBefore.count + 1)
    }

    func test_importCueList_noActiveItem_isNoOp() {
        let doc = CueListDocument() // no items, no active item
        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1]),
            mode: .replace,
            document: doc,
            undoManager: nil
        )
        XCTAssertTrue(doc.model.items.isEmpty)
    }
}
