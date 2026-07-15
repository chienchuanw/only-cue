import XCTest
@testable import OnlyCue

/// #640 — `MediaReference.bundlePath` (schema v16) is optional and encoded with
/// `encodeIfPresent`, so a normal (non-bundle) `.cuelist` is byte-unchanged: the
/// key is simply absent when nil. Only a bundle's `.cuelist` carries it.
final class MediaReferenceBundlePathTests: XCTestCase {

    private func makeMedia() -> MediaReference {
        MediaReference(displayName: "x.wav", kind: .audio, duration: 60, bookmarkData: Data([1]))
    }

    func test_encode_omitsBundlePath_whenNil() throws {
        let data = try JSONEncoder().encode(makeMedia())
        let json = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertFalse(json.contains("bundlePath"), "nil bundlePath must not appear in JSON")
    }

    func test_encode_includesBundlePath_whenPresent() throws {
        var media = makeMedia()
        media.bundlePath = "media/x.wav"
        let data = try JSONEncoder().encode(media)
        let decoded = try JSONDecoder().decode(MediaReference.self, from: data)
        XCTAssertEqual(decoded.bundlePath, "media/x.wav")
    }

    func test_decode_missingBundlePath_isNil() throws {
        let json = #"{"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"}"#
        let media = try JSONDecoder().decode(MediaReference.self, from: Data(json.utf8))
        XCTAssertNil(media.bundlePath)
    }
}
