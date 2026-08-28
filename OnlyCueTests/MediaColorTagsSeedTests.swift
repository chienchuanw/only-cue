#if DEBUG
import XCTest
@testable import OnlyCue

/// Pins the `media-color-tags` UI-test seed plan (#782). `MediaColorTagUITests`
/// counts swatches against this shape, so if the plan drifts the UI assertion
/// silently changes meaning — this suite is the tripwire that makes the drift
/// fail here, headlessly, instead of there.
final class MediaColorTagsSeedTests: XCTestCase {

    private func plan() throws -> [UITestSeedHandler.ItemSeed] {
        try UITestSeedHandler.itemSeeds(for: "media-color-tags")
    }

    func test_tagsTheOuterTwoClipsAndLeavesTheMiddleOneUntagged() throws {
        XCTAssertEqual(try plan().map(\.colorHex), [
            CuePointType.defaultPalette[3],
            nil,
            CuePointType.defaultPalette[5]
        ])
    }

    func test_everySeededTagIsAPaletteColor() throws {
        for hex in try plan().compactMap(\.colorHex) {
            XCTAssertTrue(
                CuePointType.defaultPalette.contains(hex),
                "\(hex) is not in the palette, so `setMediaColor` would reject it"
            )
        }
    }

    func test_buildsSeededProject_carryingTheTagsOntoTheMediaItems() throws {
        let project = try UITestSeedHandler.buildProject(for: "media-color-tags")
        XCTAssertEqual(project.items.count, 3)
        XCTAssertEqual(project.items.filter { $0.colorHex != nil }.count, 2)
        XCTAssertTrue(project.items.allSatisfy { !$0.media.bookmarkData.isEmpty })
    }
}
#endif
