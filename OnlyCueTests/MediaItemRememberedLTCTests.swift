import XCTest
@testable import OnlyCue

/// Persistence of `MediaItem.rememberedLTC` (#754): round-trip + backward-compat
/// decode of a v19 document that lacks the key.
final class MediaItemRememberedLTCTests: XCTestCase {

    private func makeItem() -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "a.wav", kind: .audio, duration: 10, bookmarkData: Data([0x01])),
            cues: []
        )
    }

    private let track = StripedTimecodeTrack(
        anchorTimecode: Timecode(frameCount: 108_000, rate: .fps30),
        anchorPlaybackSeconds: 3,
        ltcChannel: 1
    )

    func test_roundTripsWithRememberedLTC() throws {
        var item = makeItem()
        item.rememberedLTC = track
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(MediaItem.self, from: data).rememberedLTC, track)
    }

    func test_missingKey_decodesAsNil() throws {
        // A nil value encodes without the key (encodeIfPresent); a v19 doc that
        // never had the key decodes to nil rather than throwing.
        let data = try JSONEncoder().encode(makeItem())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("rememberedLTC"))
        XCTAssertNil(try JSONDecoder().decode(MediaItem.self, from: data).rememberedLTC)
    }
}
