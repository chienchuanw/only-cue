import XCTest
@testable import OnlyCue

/// The read-only cue markers drawn on the Mini Player progress bar (#773).
/// These four data rules are the feature's whole logic surface — the tick layer
/// itself is pure `Canvas` drawing with no branching.
///
/// Spec: `docs/superpowers/specs/2026-08-26-miniplayer-cue-markers-design.md`.
final class MiniPlayerCueMarkerTests: XCTestCase {

    // Fixed cue-type IDs so colour lookups are deterministic.
    private let amberID = UUID()
    private let tealID = UUID()

    private func types() -> [CuePointType] {
        [
            CuePointType(id: amberID, name: "Amber", colorHex: "#FFA94D"),
            CuePointType(id: tealID, name: "Teal", colorHex: "#4ECDC4")
        ]
    }

    private func cue(_ name: String, _ time: TimeInterval, _ typeID: UUID) -> Cue {
        Cue(id: UUID(), typeID: typeID, cueNumber: nil, name: name, time: time, notes: "", fadeTime: .zero)
    }

    private func markers(
        _ cues: [Cue],
        duration: TimeInterval = 120,
        types: [CuePointType]? = nil,
        editorMode: EditorMode = .cue,
        showGoTypeID: CuePointType.ID? = nil
    ) -> [MiniPlayerModel.CueMarker] {
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "Dialogue — Scene 2.wav",
                kind: .audio,
                duration: duration,
                bookmarkData: Data([0x00])
            ),
            cues: cues
        )
        return MiniPlayerModel.make(
            currentTime: 0,
            duration: duration,
            item: item,
            timecodeSettings: ProjectTimecodeSettings(framerate: .fps30),
            cuePointTypes: types ?? self.types(),
            editorMode: editorMode,
            showGoTypeID: showGoTypeID
        ).cueMarkers
    }

    /// Rules 3 + 4: the fraction is `time / duration` and the colour is the
    /// cue type's, emitted in time order regardless of the stored cue order.
    func test_fractionsAndColorsInTimeOrder() {
        XCTAssertEqual(
            markers([cue("Verse 1", 30, tealID), cue("Lights Up", 10, amberID), cue("Chorus", 60, amberID)]),
            [
                .init(fraction: 10.0 / 120, colorHex: "#FFA94D"),
                .init(fraction: 30.0 / 120, colorHex: "#4ECDC4"),
                .init(fraction: 60.0 / 120, colorHex: "#FFA94D")
            ]
        )
    }

    /// Rule 1: a cue type hidden in the main window is hidden here too.
    func test_excludeInvisibleTypes() {
        let hidden = [
            CuePointType(id: amberID, name: "Amber", colorHex: "#FFA94D", isVisible: false),
            CuePointType(id: tealID, name: "Teal", colorHex: "#4ECDC4")
        ]
        XCTAssertEqual(
            markers([cue("Lights Up", 10, amberID), cue("Verse 1", 30, tealID)], types: hidden),
            [.init(fraction: 30.0 / 120, colorHex: "#4ECDC4")]
        )
    }

    /// Rule 1: an unresolvable `typeID` has no colour, so it has no tick.
    func test_excludeUnresolvedTypes() {
        XCTAssertEqual(
            markers([cue("Orphan", 10, UUID()), cue("Verse 1", 30, tealID)]),
            [.init(fraction: 30.0 / 120, colorHex: "#4ECDC4")]
        )
    }

    /// Rule 2: times outside `[0, duration]` are dropped rather than clamped —
    /// clamping would fabricate a fake thick tick at the edge. Bounds are kept.
    func test_skipOutOfRangeTimesAndKeepBounds() {
        XCTAssertEqual(
            markers([
                cue("Before", -5, amberID),
                cue("At zero", 0, amberID),
                cue("At end", 120, tealID),
                cue("After", 130, tealID)
            ]),
            [.init(fraction: 0, colorHex: "#FFA94D"), .init(fraction: 1, colorHex: "#4ECDC4")]
        )
    }

    /// Rule 2: an unknown clip length means nothing can be positioned.
    func test_emptyWhenDurationUnknown() {
        XCTAssertTrue(markers([cue("Lights Up", 10, amberID)], duration: 0).isEmpty)
    }

    func test_emptyWhenNoMedia() {
        let model = MiniPlayerModel.make(
            currentTime: 0,
            duration: 120,
            item: nil,
            timecodeSettings: ProjectTimecodeSettings(framerate: .fps30),
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertTrue(model.cueMarkers.isEmpty)
    }

    /// Decision 3: the overview is identical in both modes — the Show-mode type
    /// filter narrows GO and cue stepping, never the timeline.
    func test_ignoreShowGoTypeFilter() {
        let cues = [cue("Lights Up", 10, amberID), cue("Verse 1", 30, tealID)]
        XCTAssertEqual(
            markers(cues, editorMode: .show, showGoTypeID: amberID),
            markers(cues)
        )
    }

    /// Decision 4: coincident cues are neither merged nor bucketed — a dense
    /// stretch is *meant* to read as a solid block.
    func test_keepDuplicatesAtTheSameTime() {
        XCTAssertEqual(markers([cue("A", 30, amberID), cue("B", 30, tealID)]).count, 2)
    }
}
