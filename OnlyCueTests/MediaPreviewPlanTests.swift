import XCTest
@testable import OnlyCue

final class MediaPreviewPlanTests: XCTestCase {

    private func validBookmark() throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        try Data("x".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try Bookmarks.create(for: url)
    }

    func test_audio_validBookmark_isWaveform() throws {
        let plan = MediaPreviewPlan.make(kind: .audio, bookmarkData: try validBookmark())
        guard case .waveform = plan else { return XCTFail("expected .waveform, got \(plan)") }
    }

    func test_video_validBookmark_isPoster() throws {
        let plan = MediaPreviewPlan.make(kind: .video, bookmarkData: try validBookmark())
        guard case .poster = plan else { return XCTFail("expected .poster, got \(plan)") }
    }

    func test_garbageBookmark_isUnavailable() {
        let plan = MediaPreviewPlan.make(kind: .audio, bookmarkData: Data([0x00]))
        XCTAssertEqual(plan, .unavailable)
    }
}
