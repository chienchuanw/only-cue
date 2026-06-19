import XCTest
@testable import OnlyCue

/// #587 — media should auto-relink when the file is still at (or near) its saved
/// path. `MediaRelocator` reads the original path cached inside the existing
/// security-scoped bookmark blob (no file needed, no resolve) and finds the
/// first candidate that still exists on disk.
final class MediaRelocatorTests: XCTestCase {

    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relocator-\(UUID().uuidString).wav")
        try Data([0x00, 0x01]).write(to: url)
        return url
    }

    func test_cachedPath_readsOriginalPathFromBookmark() throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let bookmark = try Bookmarks.create(for: file)

        let path = try XCTUnwrap(MediaRelocator.cachedPath(fromBookmark: bookmark))
        XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, file.lastPathComponent)
    }

    func test_candidateURLs_includeTheStillExistingFile() throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let bookmark = try Bookmarks.create(for: file)

        let candidates = MediaRelocator.candidateURLs(bookmark: bookmark, displayName: file.lastPathComponent)
        XCTAssertTrue(candidates.contains { $0.lastPathComponent == file.lastPathComponent })
        XCTAssertNotNil(MediaRelocator.firstExisting(candidates))
    }

    func test_firstExisting_picksTheExistingURL() throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let missing = file.deletingLastPathComponent()
            .appendingPathComponent("missing-\(UUID().uuidString).wav")

        XCTAssertEqual(MediaRelocator.firstExisting([missing, file]), file)
    }

    func test_firstExisting_nilWhenNoneExist() {
        let a = URL(fileURLWithPath: "/no/such/path/a.wav")
        let b = URL(fileURLWithPath: "/no/such/path/b.wav")
        XCTAssertNil(MediaRelocator.firstExisting([a, b]))
    }

    func test_cachedPath_nilForGarbageData() {
        XCTAssertNil(MediaRelocator.cachedPath(fromBookmark: Data([0x00, 0x01, 0x02])))
    }
}
