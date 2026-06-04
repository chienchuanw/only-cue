#if DEBUG
import XCTest
@testable import OnlyCue

/// Pins the `set-list-act-i` UI-test seed plan (#416) to the Figma reference
/// (Cue frame `318:1228`, Lyric frame `318:1369`): 8 mixed video/audio media
/// items, an active audio clip carrying 6 named/faded/colored cues, and a
/// 12-line lyric sheet (4 placed + 8 unplaced). Pure plan assertions — no
/// fixture IO, so this runs fast in the unit host.
final class SetListActISeedTests: XCTestCase {

    private func plan() throws -> [UITestSeedHandler.ItemSeed] {
        try UITestSeedHandler.itemSeeds(for: "set-list-act-i")
    }

    func test_hasEightMediaItems_mixedKinds() throws {
        let seeds = try plan()
        XCTAssertEqual(seeds.count, 8)
        XCTAssertEqual(
            seeds.map(\.displayName),
            [
                "Act I — Opening.wav",
                "Dialogue — Scene 2.wav",
                "Projection — Storm.mp4",
                "Underscore — Bridge.wav",
                "Set Change.mov",
                "Finale.wav",
                "Curtain Call.mov",
                "Ambient Loop.wav"
            ]
        )
        XCTAssertEqual(
            seeds.map(\.kind),
            [.audio, .audio, .video, .audio, .video, .audio, .video, .audio]
        )
    }

    func test_exactlyOneActiveItem_isDialogue() throws {
        let seeds = try plan()
        let active = seeds.filter(\.isActive)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.displayName, "Dialogue — Scene 2.wav")
    }

    func test_activeItemHasSixNamedFadedNumberedCues() throws {
        let active = try XCTUnwrap(plan().first(where: \.isActive))
        XCTAssertEqual(active.cues.map(\.name),
                       ["Lights Up", "Verse 1", "Chorus Hit", "Bridge", "Final Chorus", "Blackout"])
        XCTAssertEqual(active.cues.map(\.time), [18, 90, 165, 242, 320, 408])
        XCTAssertEqual(active.cues.map(\.fadeTime.fadeIn), [1.5, 2.0, 0.5, 3.0, 2.0, 1.0])
        XCTAssertEqual(active.cues.compactMap(\.cueNumber), [1, 2, 3, 4, 5, 6])
    }

    func test_activeItemHasTwelveLyrics_fourPlacedEightUnplaced() throws {
        let active = try XCTUnwrap(plan().first(where: \.isActive))
        XCTAssertEqual(active.lyrics.lines.count, 12)
        XCTAssertEqual(active.lyrics.placedLines.count, 4)
        XCTAssertEqual(active.lyrics.unplacedLines.count, 8)
        XCTAssertEqual(active.lyrics.placedLines.first?.text, "the morning came too soon for us")
    }

    func test_nonActiveItemsCarryNoCuesOrLyrics() throws {
        for seed in try plan() where !seed.isActive {
            XCTAssertTrue(seed.cues.isEmpty, "\(seed.displayName) should have no cues")
            XCTAssertTrue(seed.lyrics.lines.isEmpty, "\(seed.displayName) should have no lyrics")
        }
    }

    func test_cueTypesMatchFigmaPalette() throws {
        let colors = UITestSeedHandler.cueTypes(for: "set-list-act-i").map(\.colorHex)
        XCTAssertEqual(colors, ["#FFA94D", "#4ECDC4", "#FFD93D", "#9D7EE0", "#4D96FF", "#FF6B6B"])
    }

    func test_legacySeedRemainsSingleItem() throws {
        // Regression: the pre-existing seeds keep their single-item shape.
        XCTAssertEqual(try UITestSeedHandler.itemSeeds(for: "three-cues-1-3-6").count, 1)
        XCTAssertEqual(try UITestSeedHandler.itemSeeds(for: "song-with-lyrics").count, 1)
    }

    /// Exercises the full build path — staging each bundled fixture and creating
    /// its bookmark — so a missing/mis-bundled fixture fails here, not only on
    /// the Mac-mini UI run.
    func test_buildsSeededProject_withBundledFixtures() throws {
        let project = try UITestSeedHandler.buildProject(for: "set-list-act-i")
        XCTAssertEqual(project.items.count, 8)
        XCTAssertEqual(project.cuePointTypes.count, 6)
        let active = try XCTUnwrap(project.activeItem)
        XCTAssertEqual(active.media.displayName, "Dialogue — Scene 2.wav")
        XCTAssertEqual(active.cues.count, 6)
        XCTAssertEqual(active.lyrics.lines.count, 12)
        // Every item bookmarked a real staged fixture.
        XCTAssertTrue(project.items.allSatisfy { !$0.media.bookmarkData.isEmpty })
        // Each cue resolves to one of the project's six colored types.
        let typeIDs = Set(project.cuePointTypes.map(\.id))
        XCTAssertTrue(active.cues.allSatisfy { typeIDs.contains($0.typeID) })
    }
}
#endif
