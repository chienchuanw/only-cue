import XCTest
@testable import OnlyCue

/// #715 — `MediaItem.playsOriginalSourceAudio` round-trip and default tests.
final class MediaItemSourceAudioTests: XCTestCase {

    private func makeItem(playsOriginalSourceAudio: Bool) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "fixture.wav",
                kind: .audio,
                duration: 60,
                bookmarkData: Data()
            ),
            cues: [],
            playsOriginalSourceAudio: playsOriginalSourceAudio
        )
    }

    func test_playsOriginalSourceAudio_defaultIsFalse() {
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "fixture.wav",
                kind: .audio,
                duration: 60,
                bookmarkData: Data()
            ),
            cues: []
        )
        XCTAssertFalse(
            item.playsOriginalSourceAudio,
            "music-only (false) must be the default — keeps the LTC tone muted for existing clips"
        )
    }

    func test_playsOriginalSourceAudio_roundTrip_true() throws {
        let original = makeItem(playsOriginalSourceAudio: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)
        XCTAssertTrue(decoded.playsOriginalSourceAudio)
    }

    func test_playsOriginalSourceAudio_roundTrip_false() throws {
        let original = makeItem(playsOriginalSourceAudio: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)
        XCTAssertFalse(decoded.playsOriginalSourceAudio)
    }

    func test_playsOriginalSourceAudio_missingKeyDefaultsFalse() throws {
        // Simulate a JSON blob that lacks the new key (e.g., a legacy item).
        let json = """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
          "cues": [],
          "startTimecodeFrames": 0,
          "ltcMuted": false,
          "alternateName": null,
          "lyrics": {"offsetSeconds": 0, "lines": []}
        }
        """
        let decoded = try JSONDecoder().decode(MediaItem.self, from: Data(json.utf8))
        XCTAssertFalse(
            decoded.playsOriginalSourceAudio,
            "missing key must resolve to false — music-only is the safe default"
        )
    }
}
