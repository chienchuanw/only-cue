import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsGridTests: XCTestCase {

    /// A document with one 10 s audio item; pass a tempo map (default: 120 BPM 4/4 whole item).
    private func makeDocument(tempoMap: TempoMap = TempoMap.singleSection(bpm: 120, beatsPerBar: 4)) -> CueListDocument {
        let doc = CueListDocument()
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "song.wav", kind: .audio, duration: 10, bookmarkData: Data([0x00])),
            cues: [],
            tempoMap: tempoMap
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id
        return doc
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func activeCues(_ doc: CueListDocument) -> [Cue] {
        doc.model.activeItem?.cues ?? []
    }

    private func map(_ doc: CueListDocument) -> TempoMap {
        doc.model.activeItem?.tempoMap ?? TempoMap()
    }

    // MARK: - snapCues(toBeatIn:) / toBarIn:

    func test_snapCues_toBeat_movesEverySelectedCueToNearestBeat_inOneUndoStep() {
        let doc = makeDocument()                       // beats every 0.5 s
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2.1, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 3.0, document: doc, undoManager: undo)
        let selection = Set(activeCues(doc).map(\.id))

        CueCommands.snapCues(selection, toBeatIn: map(doc), itemDuration: 10, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).map(\.time), [0.5, 2.0, 3.0])

        undo.undo()
        XCTAssertEqual(activeCues(doc).map(\.time).sorted(), [0.7, 2.1, 3.0])
    }

    func test_snapCues_toBar_movesEverySelectedCueToNearestDownbeat() {
        let doc = makeDocument()                       // bars every 2.0 s
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2.1, document: doc, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 3.0, document: doc, undoManager: undo)
        let selection = Set(activeCues(doc).map(\.id))

        CueCommands.snapCues(selection, toBarIn: map(doc), itemDuration: 10, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).map(\.time), [0.0, 2.0, 4.0])
    }

    func test_snapCues_toGrid_emptyMap_isNoOp() {
        let doc = makeDocument(tempoMap: TempoMap())
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        let selection = Set(activeCues(doc).map(\.id))
        CueCommands.snapCues(selection, toBeatIn: map(doc), itemDuration: 10, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).map(\.time), [0.7], "an empty tempo map snaps nothing")
    }

    func test_snapCues_toGrid_emptySelection_isNoOp() {
        let doc = makeDocument()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.7, document: doc, undoManager: undo)
        CueCommands.snapCues([], toBeatIn: map(doc), itemDuration: 10, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).map(\.time), [0.7])
    }

    // MARK: - addCuesOnGrid

    func test_addCuesOnGrid_everyBeat_insertsACueAtEachBeat_inOneUndoStep() throws {
        let doc = makeDocument()                       // beats every 0.5 s; [0, 10) → 0…9.5 (20 beats)
        let undo = makeUndoManager()
        CueCommands.addCuesOnGrid(in: 0...10, every: .beat, type: nil, document: doc, undoManager: undo)

        let cues = activeCues(doc)
        XCTAssertEqual(cues.count, 20)
        XCTAssertEqual(cues.map(\.time), (0..<20).map { Double($0) * 0.5 })
        let defaultType = try XCTUnwrap(doc.model.defaultCuePointTypeID)
        XCTAssertTrue(cues.allSatisfy { $0.typeID == defaultType })
        XCTAssertEqual(cues.map(\.cueNumber), (1...20).map(Double.init))

        undo.undo()
        XCTAssertTrue(activeCues(doc).isEmpty, "the bulk insert is one undo step")
    }

    func test_addCuesOnGrid_everyBar_insertsACueAtEachDownbeat() {
        let doc = makeDocument()                       // bars every 2.0 s; [0, 10) → 0, 2, 4, 6, 8
        let undo = makeUndoManager()
        CueCommands.addCuesOnGrid(in: 0...10, every: .bar, type: nil, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).map(\.time), [0.0, 2.0, 4.0, 6.0, 8.0])
    }

    func test_addCuesOnGrid_emptyMap_isNoOp() {
        let doc = makeDocument(tempoMap: TempoMap())
        let undo = makeUndoManager()
        CueCommands.addCuesOnGrid(in: 0...10, every: .beat, type: nil, document: doc, undoManager: undo)
        XCTAssertTrue(activeCues(doc).isEmpty)
        XCTAssertFalse(undo.canUndo, "no cues added → no undo step")
    }

    func test_addCuesOnGrid_restrictedRange_onlyInsertsWithinIt() {
        let doc = makeDocument()                       // beats every 0.5 s
        let undo = makeUndoManager()
        CueCommands.addCuesOnGrid(in: 3...5, every: .beat, type: nil, document: doc, undoManager: undo)
        XCTAssertEqual(activeCues(doc).map(\.time), [3.0, 3.5, 4.0, 4.5, 5.0])
    }
}
