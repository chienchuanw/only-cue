import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsSetTempoTests: XCTestCase {

    func testSetCueTempoStoresValues() {
        let env = makeDocWithOneCue()
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: 120,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: nil
        )
        let cue = env.doc.model.items[0].cues[0]
        XCTAssertEqual(cue.bpm, 120)
        XCTAssertEqual(cue.beatsPerBar, 4)
    }

    func testSetCueTempoNilClearsBoth() {
        let env = makeDocWithOneCue()
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: 120,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: nil
        )
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: nil,
            beatsPerBar: nil,
            item: env.itemID,
            document: env.doc,
            undoManager: nil
        )
        let cue = env.doc.model.items[0].cues[0]
        XCTAssertNil(cue.bpm)
        XCTAssertNil(cue.beatsPerBar)
    }

    func testSetCueTempoIsUndoable() {
        let env = makeDocWithOneCue()
        let undo = UndoManager()
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: 120,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: undo
        )
        XCTAssertEqual(env.doc.model.items[0].cues[0].bpm, 120)
        undo.undo()
        XCTAssertNil(env.doc.model.items[0].cues[0].bpm)
        undo.redo()
        XCTAssertEqual(env.doc.model.items[0].cues[0].bpm, 120)
    }

    func testSetCueTempoClampsBPMAndMeter() {
        let env = makeDocWithOneCue()
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: 9999,
            beatsPerBar: 99,
            item: env.itemID,
            document: env.doc,
            undoManager: nil
        )
        XCTAssertEqual(env.doc.model.items[0].cues[0].bpm, 400)
        XCTAssertEqual(env.doc.model.items[0].cues[0].beatsPerBar, 16)
    }

    func testSetCueTempoOnUnknownCueIsNoOp() {
        let env = makeDocWithOneCue()
        let snapshot = env.doc.model
        CueCommands.setCueTempo(
            cueID: UUID(),
            bpm: 120,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: nil
        )
        XCTAssertEqual(env.doc.model, snapshot)
    }

    func testSetCueTempoNaNBPMResolvesToNil() {
        let env = makeDocWithOneCue()
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: .nan,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: nil
        )
        XCTAssertNil(env.doc.model.items[0].cues[0].bpm, "NaN must not reach the model")
    }

    func testSetCueTempoInfinityBPMResolvesToNil() {
        let env = makeDocWithOneCue()
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: .infinity,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: nil
        )
        XCTAssertNil(env.doc.model.items[0].cues[0].bpm, "infinity must not reach the model")
    }

    func testSetCueTempoSameValueIsNoOp() {
        let env = makeDocWithOneCue()
        let undo = UndoManager()
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: 120,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: undo
        )
        XCTAssertTrue(undo.canUndo)
        let undoBefore = undo.canUndo
        // Same values: should not register a second undo step.
        CueCommands.setCueTempo(
            cueID: env.cueID,
            bpm: 120,
            beatsPerBar: 4,
            item: env.itemID,
            document: env.doc,
            undoManager: undo
        )
        undo.undo()
        XCTAssertEqual(undoBefore, undo.canUndo == false)
    }

    // MARK: - Helpers

    private struct Env {
        let doc: CueListDocument
        let cueID: Cue.ID
        let itemID: MediaItem.ID
    }

    private func makeDocWithOneCue() -> Env {
        let typeID = UUID()
        let cueID = UUID()
        let itemID = UUID()
        let doc = CueListDocument()
        doc.model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "t",
            cuePointTypes: [CuePointType(id: typeID, name: "G", colorHex: "#fff")],
            items: [MediaItem(
                id: itemID,
                media: MediaReference(
                    displayName: "x", kind: .audio, duration: 10, bookmarkData: Data()
                ),
                cues: [Cue(
                    id: cueID,
                    typeID: typeID,
                    cueNumber: nil,
                    name: "c",
                    time: 1.0,
                    notes: "",
                    fadeTime: .zero
                )]
            )],
            activeItemID: itemID
        )
        return Env(doc: doc, cueID: cueID, itemID: itemID)
    }
}
