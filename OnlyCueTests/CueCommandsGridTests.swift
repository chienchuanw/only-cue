import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsGridTests: XCTestCase {

    /// A document with one 10 s audio item. The active item's cue list is set up
    /// to provide a 120 BPM 4/4 grid (BPM cue at time 0) by default.
    private func makeDocument(addBPMAnchorCue: Bool = true) -> (CueListDocument, UUID) {
        let doc = CueListDocument()
        let typeID = UUID()
        doc.model.cuePointTypes = [CuePointType(id: typeID, name: "G", colorHex: "#fff")]
        var cues: [Cue] = []
        if addBPMAnchorCue {
            cues.append(Cue(
                id: UUID(),
                typeID: typeID,
                cueNumber: nil,
                name: "anchor",
                time: 0,
                notes: "",
                fadeTime: .zero,
                bpm: 120,
                beatsPerBar: 4
            ))
        }
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "song.wav", kind: .audio, duration: 10, bookmarkData: Data([0x00])),
            cues: cues
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id
        return (doc, typeID)
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func activeCues(_ doc: CueListDocument) -> [Cue] {
        doc.model.activeItem?.cues ?? []
    }

    private func grid(_ doc: CueListDocument) -> DerivedTempoGrid {
        guard let item = doc.model.activeItem else { return DerivedTempoGrid(segments: []) }
        return DerivedTempoGrid.from(cues: item.cues, itemDuration: item.media.duration)
    }

    // MARK: - snapCues(toBeatIn:) / toBarIn:

    func test_snapCues_toBeat_movesEverySelectedNonAnchorCueToNearestBeat_inOneUndoStep() {
        let (doc, _) = makeDocument()                 // beats every 0.5 s
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2.1, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 3.0, document: doc, undoManager: undo)
        // Anchor cue is the one at time 0 with bpm; exclude from selection.
        let selection = Set(activeCues(doc).filter { $0.bpm == nil }.map(\.id))

        CueCommands.snapCues(selection, toBeatIn: grid(doc), itemDuration: 10, document: doc, undoManager: undo)
        let nonAnchor = activeCues(doc).filter { $0.bpm == nil }.map(\.time)
        XCTAssertEqual(nonAnchor, [0.5, 2.0, 3.0])
    }

    func test_snapCues_toBar_movesEverySelectedCueToNearestDownbeat() {
        let (doc, _) = makeDocument()                 // bars every 2.0 s
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2.1, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 3.0, document: doc, undoManager: undo)
        let selection = Set(activeCues(doc).filter { $0.bpm == nil }.map(\.id))

        CueCommands.snapCues(selection, toBarIn: grid(doc), itemDuration: 10, document: doc, undoManager: undo)
        let nonAnchor = activeCues(doc).filter { $0.bpm == nil }.map(\.time)
        XCTAssertEqual(nonAnchor, [0.0, 2.0, 4.0])
    }

    func test_snapCues_toGrid_emptyGrid_isNoOp() {
        let (doc, _) = makeDocument(addBPMAnchorCue: false)
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        let selection = Set(activeCues(doc).map(\.id))
        CueCommands.snapCues(selection, toBeatIn: grid(doc), itemDuration: 10, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).map(\.time), [0.7], "an empty grid snaps nothing")
    }

    func test_snapCues_toGrid_emptySelection_isNoOp() {
        let (doc, _) = makeDocument()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        CueCommands.snapCues([], toBeatIn: grid(doc), itemDuration: 10, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).filter { $0.bpm == nil }.map(\.time), [0.7])
    }
}
