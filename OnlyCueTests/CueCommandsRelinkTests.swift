import XCTest
@testable import OnlyCue

/// #577 — "Relink media" must repoint an existing media item at a newly chosen
/// file (preserving its id, cues, lyrics, timecode), not import a new item.
/// These pin the pure command/model seam; the bookmark + AVURLAsset boundary
/// and the picker wiring are verified by a manual run.
@MainActor
final class CueCommandsRelinkTests: XCTestCase {

    private func makeCue() -> Cue {
        Cue(id: UUID(), typeID: UUID(), cueNumber: 1, name: "Hit", time: 5, notes: "", fadeTime: .zero)
    }

    private func makeItem(
        name: String,
        cues: [Cue],
        startTimecodeFrames: Int = 0,
        ltcMuted: Bool = false,
        alternateName: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: name, kind: .audio, duration: 60, bookmarkData: Data([0x00])),
            cues: cues,
            startTimecodeFrames: startTimecodeFrames,
            ltcMuted: ltcMuted,
            alternateName: alternateName
        )
    }

    private func makeDocument(items: [MediaItem]) -> CueListDocument {
        let doc = CueListDocument()
        doc.model.items = items
        doc.model.activeItemID = items.first?.id
        return doc
    }

    func test_relink_repointsExistingItem_preservingIdAndCues() {
        let cue = makeCue()
        let item = makeItem(
            name: "old.wav",
            cues: [cue],
            startTimecodeFrames: 600,
            ltcMuted: true,
            alternateName: "Intro"
        )
        let doc = makeDocument(items: [item])
        let newMedia = MediaReference(displayName: "new.wav", kind: .audio, duration: 90, bookmarkData: Data([0x01, 0x02]))

        CueCommands.relinkMedia(itemID: item.id, to: newMedia, in: doc, undoManager: nil)

        XCTAssertEqual(doc.model.items.count, 1, "Relink must not create a new item")
        XCTAssertEqual(doc.model.items[0].id, item.id, "Item identity must be preserved")
        XCTAssertEqual(doc.model.items[0].cues.map(\.id), [cue.id], "Cues must be preserved")
        XCTAssertEqual(doc.model.items[0].media, newMedia, "Media reference must be replaced")
        // Non-media item fields must survive a relink untouched.
        XCTAssertEqual(doc.model.items[0].startTimecodeFrames, 600)
        XCTAssertTrue(doc.model.items[0].ltcMuted)
        XCTAssertEqual(doc.model.items[0].alternateName, "Intro")
    }

    func test_relink_isUndoable() {
        let item = makeItem(name: "old.wav", cues: [])
        let oldMedia = item.media
        let doc = makeDocument(items: [item])
        let undo = UndoManager()
        let newMedia = MediaReference(displayName: "new.mov", kind: .video, duration: 90, bookmarkData: Data([0x09]))

        CueCommands.relinkMedia(itemID: item.id, to: newMedia, in: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items[0].media, newMedia)

        undo.undo()
        XCTAssertEqual(doc.model.items[0].media, oldMedia, "Undo must restore the prior media reference")
    }

    func test_relink_unknownID_isNoOp() {
        let item = makeItem(name: "old.wav", cues: [])
        let doc = makeDocument(items: [item])
        let newMedia = MediaReference(displayName: "new.wav", kind: .audio, duration: 90, bookmarkData: Data([0x07]))

        CueCommands.relinkMedia(itemID: UUID(), to: newMedia, in: doc, undoManager: nil)

        XCTAssertEqual(doc.model.items.count, 1)
        XCTAssertEqual(doc.model.items[0].media.displayName, "old.wav")
    }
}
