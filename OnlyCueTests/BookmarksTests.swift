import XCTest
@testable import OnlyCue

final class BookmarksTests: XCTestCase {

    func test_roundTrip_resolvesToOriginalURL() throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Bookmarks.create(for: url)
        let resolution = try Bookmarks.resolve(data)

        XCTAssertEqual(resolution.url.standardizedFileURL, url.standardizedFileURL)
        XCTAssertFalse(resolution.isStale)
    }

    func test_jsonRoundTrip_preservesBookmark() throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let original = try Bookmarks.create(for: url)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try XCTUnwrap(JSONDecoder().decode(Data?.self, from: encoded))
        let resolution = try Bookmarks.resolve(decoded)

        XCTAssertEqual(resolution.url.standardizedFileURL, url.standardizedFileURL)
    }

    func test_resolve_invalidData_throws() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try Bookmarks.resolve(garbage))
    }
}
