import XCTest
@testable import OnlyCue

/// #636 — the media context menu's "Show in Finder" item resolves a media's
/// security-scoped bookmark to the file's *current* on-disk URL (tracking
/// moves) and confirms the file still exists. A `nil` return means the file
/// can't be located, so the menu item is disabled.
final class MediaRevealTests: XCTestCase {

    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reveal-\(UUID().uuidString).wav")
        try Data([0x00, 0x01]).write(to: url)
        return url
    }

    private func makeMedia(bookmark: Data) -> MediaReference {
        MediaReference(displayName: "clip.wav", kind: .audio, duration: 0, bookmarkData: bookmark)
    }

    func test_revealURL_returnsResolvedURL_whenFileExists() throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let media = makeMedia(bookmark: try Bookmarks.create(for: file))

        let url = try XCTUnwrap(MediaReveal.revealURL(for: media))
        XCTAssertEqual(url.lastPathComponent, file.lastPathComponent)
    }

    func test_revealURL_tracksMovedFile() throws {
        let file = try makeTempFile()
        let media = makeMedia(bookmark: try Bookmarks.create(for: file))
        let moved = file.deletingLastPathComponent()
            .appendingPathComponent("reveal-moved-\(UUID().uuidString).wav")
        try FileManager.default.moveItem(at: file, to: moved)
        defer { try? FileManager.default.removeItem(at: moved) }

        let url = try XCTUnwrap(MediaReveal.revealURL(for: media))
        XCTAssertEqual(url.lastPathComponent, moved.lastPathComponent)
    }

    func test_revealURL_isNil_whenFileMissing() throws {
        let file = try makeTempFile()
        let media = makeMedia(bookmark: try Bookmarks.create(for: file))
        try FileManager.default.removeItem(at: file)

        XCTAssertNil(MediaReveal.revealURL(for: media))
    }

    func test_revealURL_isNil_whenBookmarkUnresolvable() {
        let media = makeMedia(bookmark: Data([0x00, 0x01, 0x02]))

        XCTAssertNil(MediaReveal.revealURL(for: media))
    }
}
