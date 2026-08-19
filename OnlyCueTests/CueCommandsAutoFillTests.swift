import XCTest
@testable import OnlyCue

/// #763 — `CueCommands.autoFillCueNumbers` writes the auto-filled numbers back through
/// the command seam (undoable) and targets a *specific* item so a batch push (#765) can
/// number any selected song, not just the active one.
@MainActor
final class CueCommandsAutoFillTests: XCTestCase {

    func test_autoFill_writesNumbersBack() {
        let (doc, media) = makeDocument([1, nil, 3])
        CueCommands.autoFillCueNumbers(itemID: media.id, document: doc, undoManager: nil)
        XCTAssertEqual(number(doc, media.id, media.cues[1].id), 2)
    }

    func test_autoFill_preservesExistingNumbers() {
        let (doc, media) = makeDocument([1, nil, 3])
        CueCommands.autoFillCueNumbers(itemID: media.id, document: doc, undoManager: nil)
        XCTAssertEqual(number(doc, media.id, media.cues[0].id), 1)
        XCTAssertEqual(number(doc, media.id, media.cues[2].id), 3)
    }

    func test_autoFill_undoRestoresNil_redoRefills() {
        let undo = makeUndoManager()
        let (doc, media) = makeDocument([1, nil, 3])

        CueCommands.autoFillCueNumbers(itemID: media.id, document: doc, undoManager: undo)
        XCTAssertEqual(number(doc, media.id, media.cues[1].id), 2)

        undo.undo()
        XCTAssertNil(number(doc, media.id, media.cues[1].id))

        undo.redo()
        XCTAssertEqual(number(doc, media.id, media.cues[1].id), 2)
    }

    func test_autoFill_allNumbered_isNoOp_noUndoStep() {
        let undo = makeUndoManager()
        let (doc, media) = makeDocument([1, 2, 3])
        CueCommands.autoFillCueNumbers(itemID: media.id, document: doc, undoManager: undo)
        XCTAssertFalse(undo.canUndo)
    }

    func test_autoFill_targetsGivenItem_notActive() {
        // Two items; the active one is item0, but we fill item1.
        let doc = CueListDocument()
        let active = item([1, 2])
        let target = item([nil, 5])
        doc.model.items = [active, target]
        doc.model.activeItemID = active.id

        CueCommands.autoFillCueNumbers(itemID: target.id, document: doc, undoManager: nil)

        XCTAssertEqual(number(doc, target.id, target.cues[0].id), 1)
        // Active item is untouched.
        XCTAssertEqual(number(doc, active.id, active.cues[0].id), 1)
        XCTAssertEqual(number(doc, active.id, active.cues[1].id), 2)
    }

    // MARK: helpers

    private func item(_ numbers: [Double?]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "x.wav", kind: .audio, duration: 60, bookmarkData: Data([0x00])),
            cues: numbers.enumerated().map { index, value in
                Cue(
                    id: UUID(),
                    typeID: UUID(),
                    cueNumber: value,
                    name: "c\(index)",
                    time: TimeInterval(index),
                    notes: "",
                    fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
                )
            }
        )
    }

    private func makeDocument(_ numbers: [Double?]) -> (CueListDocument, MediaItem) {
        let doc = CueListDocument()
        let media = item(numbers)
        doc.model.items = [media]
        doc.model.activeItemID = media.id
        return (doc, media)
    }

    private func number(_ doc: CueListDocument, _ itemID: MediaItem.ID, _ cueID: Cue.ID) -> Double? {
        doc.model.items.first { $0.id == itemID }?.cues.first { $0.id == cueID }?.cueNumber
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
