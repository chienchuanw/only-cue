import XCTest
@testable import OnlyCue

/// #683 — the push sheet's target parameters persist per media item via a
/// `CueCommands` mutation (never a direct `ProjectModel` write).
@MainActor
final class CueCommandsMA2Tests: XCTestCase {

    private func makeItem(name: String) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 60,
                bookmarkData: Data([0x00])
            ),
            cues: [],
            startTimecodeFrames: 0,
            ltcMuted: false,
            alternateName: nil
        )
    }

    private func makeDocument(items: [MediaItem]) -> CueListDocument {
        let doc = CueListDocument()
        doc.model.items = items
        doc.model.activeItemID = items.first?.id
        return doc
    }

    private var target: MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: 18,
            timecodeSlot: 3,
            executorPage: 2,
            executorNumber: 3,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
    }

    func test_setMA2PushTarget_persistsOnItem_othersUntouched() {
        let itemA = makeItem(name: "a.wav")
        let itemB = makeItem(name: "b.wav")
        let doc = makeDocument(items: [itemA, itemB])

        CueCommands.setMA2PushTarget(target, itemID: itemA.id, document: doc, undoManager: nil)

        XCTAssertEqual(doc.model.items.first { $0.id == itemA.id }?.ma2PushTarget, target)
        XCTAssertNil(doc.model.items.first { $0.id == itemB.id }?.ma2PushTarget)
    }

    func test_setMA2PushTarget_unknownItem_isNoop() {
        let itemA = makeItem(name: "a.wav")
        let doc = makeDocument(items: [itemA])

        CueCommands.setMA2PushTarget(target, itemID: UUID(), document: doc, undoManager: nil)

        XCTAssertNil(doc.model.items[0].ma2PushTarget)
    }

    func test_setMA2PushTarget_sameValue_registersNoUndo() {
        let itemA = makeItem(name: "a.wav")
        let doc = makeDocument(items: [itemA])
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        CueCommands.setMA2PushTarget(target, itemID: itemA.id, document: doc, undoManager: undoManager)
        XCTAssertTrue(undoManager.canUndo)
        undoManager.removeAllActions()

        CueCommands.setMA2PushTarget(target, itemID: itemA.id, document: doc, undoManager: undoManager)
        XCTAssertFalse(undoManager.canUndo)
    }

    func test_setMA2PushTarget_undo_restoresPreviousValue() {
        let itemA = makeItem(name: "a.wav")
        let doc = makeDocument(items: [itemA])
        let undoManager = UndoManager()
        // Per-call grouping (no runloop in tests) — the CueCommands test convention.
        undoManager.groupsByEvent = false

        CueCommands.setMA2PushTarget(target, itemID: itemA.id, document: doc, undoManager: undoManager)
        var changed = target
        changed.sequenceSlot = 99
        CueCommands.setMA2PushTarget(changed, itemID: itemA.id, document: doc, undoManager: undoManager)

        undoManager.undo()
        XCTAssertEqual(doc.model.items[0].ma2PushTarget, target)
        undoManager.undo()
        XCTAssertNil(doc.model.items[0].ma2PushTarget)
    }
}
