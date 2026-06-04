#if DEBUG
import XCTest
@testable import OnlyCue

/// Pins the `video-project` UI-test seed plan (#417, Figma `318:1614`): the
/// populated Set List sidebar with a *video* item active so the preview pane
/// shows video (distinguishing it from the audio-only seeds), carrying a few
/// cues that fall within the clip.
final class VideoProjectSeedTests: XCTestCase {

    private func plan() throws -> [UITestSeedHandler.ItemSeed] {
        try UITestSeedHandler.itemSeeds(for: "video-project")
    }

    func test_activeItemIsVideo_distinguishingItFromAudioSeeds() throws {
        let active = try XCTUnwrap(plan().first(where: \.isActive))
        XCTAssertEqual(active.kind, .video)
        XCTAssertEqual(active.displayName, "Projection — Storm.mp4")
    }

    func test_hasPopulatedSidebar() throws {
        let seeds = try plan()
        XCTAssertEqual(seeds.count, 8)
        XCTAssertEqual(seeds.filter(\.isActive).count, 1)
    }

    func test_activeVideoHasAFewCues_allWithinTheClip() throws {
        let active = try XCTUnwrap(plan().first(where: \.isActive))
        XCTAssertFalse(active.cues.isEmpty)
        XCTAssertEqual(active.cues.map(\.name), ["Storm In", "Lightning", "Rain Peak", "Storm Out"])
        let lastCue = try XCTUnwrap(active.cues.map(\.time).max())
        XCTAssertLessThanOrEqual(
            lastCue,
            active.duration,
            "every cue must fall within the active video clip"
        )
    }

    func test_buildsSeededProject_withBundledVideoFixture() throws {
        let project = try UITestSeedHandler.buildProject(for: "video-project")
        XCTAssertEqual(project.items.count, 8)
        let active = try XCTUnwrap(project.activeItem)
        XCTAssertEqual(active.media.kind, .video)
        XCTAssertFalse(active.cues.isEmpty)
        XCTAssertTrue(project.items.allSatisfy { !$0.media.bookmarkData.isEmpty })
    }
}
#endif
