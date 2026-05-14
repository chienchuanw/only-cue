import XCTest
@testable import OnlyCue

final class MediaItemResolvedNameTests: XCTestCase {

    private func makeItem(displayName: String, alternateName: String? = nil) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: displayName,
                kind: .audio,
                duration: 60,
                bookmarkData: Data([0x00])
            ),
            cues: [],
            startTimecodeFrames: 0,
            ltcMuted: false,
            alternateName: alternateName
        )
    }

    func test_resolvedName_returnsFileBasename_whenAlternateIsNil() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: nil).resolvedName, "track.wav")
    }

    func test_resolvedName_returnsFileBasename_whenAlternateIsEmpty() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: "").resolvedName, "track.wav")
    }

    func test_resolvedName_returnsFileBasename_whenAlternateIsWhitespace() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: "   \n\t").resolvedName, "track.wav")
    }

    func test_resolvedName_returnsTrimmedAlternate_whenSet() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: "  Opening  ").resolvedName, "Opening")
    }

    func test_alternateName_defaultsToNil() {
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "a.wav",
                kind: .audio,
                duration: 60,
                bookmarkData: Data([0x00])
            ),
            cues: []
        )
        XCTAssertNil(item.alternateName)
    }
}
