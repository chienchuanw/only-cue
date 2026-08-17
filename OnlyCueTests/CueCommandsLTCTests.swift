import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsLTCTests: XCTestCase {

    private func makeItem() -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "a.wav", kind: .audio, duration: 10, bookmarkData: Data([0x01])),
            cues: []
        )
    }

    private func track(channel: Int) -> StripedTimecodeTrack {
        StripedTimecodeTrack(
            anchorTimecode: Timecode(frameCount: 108_000, rate: .fps30),
            anchorPlaybackSeconds: 0,
            ltcChannel: channel
        )
    }

    private func seed(_ items: [MediaItem]) -> CueListDocument {
        let document = CueListDocument()
        document.model.items = items
        return document
    }

    func test_rememberLTC_writesWhenNil() {
        let item = makeItem()
        let document = seed([item])
        let t = track(channel: 1)
        CueCommands.rememberLTC(t, forItemID: item.id, document: document)
        XCTAssertEqual(document.model.items[0].rememberedLTC, t)
    }

    func test_rememberLTC_doesNotOverwriteExisting() {
        var item = makeItem()
        let original = track(channel: 1)
        item.rememberedLTC = original
        let document = seed([item])
        CueCommands.rememberLTC(track(channel: 2), forItemID: item.id, document: document)
        XCTAssertEqual(document.model.items[0].rememberedLTC, original, "write-once: must not overwrite")
    }

    func test_rememberLTC_ignoresUnknownID() {
        let item = makeItem()
        let document = seed([item])
        CueCommands.rememberLTC(track(channel: 1), forItemID: UUID(), document: document)
        XCTAssertNil(document.model.items[0].rememberedLTC)
    }

    func test_clearRememberedLTC_nils() {
        var item = makeItem()
        item.rememberedLTC = track(channel: 1)
        let document = seed([item])
        CueCommands.clearRememberedLTC(forItemID: item.id, document: document)
        XCTAssertNil(document.model.items[0].rememberedLTC)
    }
}
