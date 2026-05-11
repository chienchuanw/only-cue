import XCTest
@testable import OnlyCue

/// Pins `TimelineBreakdownLayout`: one lane per *visible* CuePointType in model
/// order, each carrying only its Type's cues (in cue order), invisible Types
/// excluded, empty Types still get a lane, stray-typed cues dropped, and the
/// hidden count.
final class TimelineBreakdownLayoutTests: XCTestCase {

    private let lightingID = UUID()
    private let soundID = UUID()
    private let videoID = UUID()

    private func types(soundVisible: Bool = true) -> [CuePointType] {
        [
            CuePointType(id: lightingID, name: "Lighting", colorHex: "#FF0000"),
            CuePointType(id: soundID, name: "Sound", colorHex: "#00FF00", isVisible: soundVisible),
            CuePointType(id: videoID, name: "Video", colorHex: "#0000FF")
        ]
    }

    private func cue(_ typeID: UUID, time: TimeInterval) -> Cue {
        Cue(id: UUID(), typeID: typeID, cueNumber: 0, name: "C", time: time, notes: "", fadeTime: .zero)
    }

    func test_oneLanePerVisibleType_inModelOrder() {
        let lanes = TimelineBreakdownLayout.lanes(cues: [], types: types())
        XCTAssertEqual(lanes.map(\.name), ["Lighting", "Sound", "Video"])
        XCTAssertEqual(lanes.map(\.typeID), [lightingID, soundID, videoID])
        XCTAssertEqual(lanes.map(\.colorHex), ["#FF0000", "#00FF00", "#0000FF"])
    }

    func test_invisibleType_isExcluded() {
        let lanes = TimelineBreakdownLayout.lanes(cues: [], types: types(soundVisible: false))
        XCTAssertEqual(lanes.map(\.name), ["Lighting", "Video"])
    }

    func test_eachLane_carriesOnlyItsTypesCues_inOrder() {
        let cues = [cue(lightingID, time: 5), cue(soundID, time: 10), cue(lightingID, time: 15)]
        let lanes = TimelineBreakdownLayout.lanes(cues: cues, types: types())
        XCTAssertEqual(lanes.first { $0.typeID == lightingID }?.cues.map(\.time), [5, 15])
        XCTAssertEqual(lanes.first { $0.typeID == soundID }?.cues.map(\.time), [10])
        XCTAssertEqual(lanes.first { $0.typeID == videoID }?.cues, [])
    }

    func test_cueWithUnknownType_isDropped() {
        let lanes = TimelineBreakdownLayout.lanes(cues: [cue(UUID(), time: 5)], types: types())
        XCTAssertTrue(lanes.allSatisfy { $0.cues.isEmpty })
    }

    func test_hiddenCount() {
        XCTAssertEqual(TimelineBreakdownLayout.hiddenCount(types: types()), 0)
        XCTAssertEqual(TimelineBreakdownLayout.hiddenCount(types: types(soundVisible: false)), 1)
    }
}
