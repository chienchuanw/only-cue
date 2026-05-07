import XCTest
@testable import OnlyCue

@MainActor
final class PreviewPaneTests: XCTestCase {

    func test_previewKind_nilMedia_isEmpty() {
        XCTAssertEqual(PreviewPane.previewKind(for: nil), .empty)
    }

    func test_previewKind_audioMedia_isAudio() {
        let media = MediaReference(displayName: "song.mp3", kind: .audio, duration: 1, bookmarkData: Data())
        XCTAssertEqual(PreviewPane.previewKind(for: media), .audio)
    }

    func test_previewKind_videoMedia_isVideo() {
        let media = MediaReference(displayName: "clip.mp4", kind: .video, duration: 1, bookmarkData: Data())
        XCTAssertEqual(PreviewPane.previewKind(for: media), .video)
    }
}
