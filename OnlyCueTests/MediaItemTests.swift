import XCTest
@testable import OnlyCue

final class MediaItemTests: XCTestCase {

    private func makeCue(time: TimeInterval) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1.0,
            name: "Cue",
            time: time,
            notes: "",
            fadeTime: .zero
        )
    }

    private func makeItem(cueTimes: [TimeInterval]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "fixture.wav",
                kind: .audio,
                duration: 100,
                bookmarkData: Data()
            ),
            cues: cueTimes.map { makeCue(time: $0) }
        )
    }

    // MARK: - .previous

    func test_cueSteppingPrevious_returnsLastCueStrictlyBeforeCurrentTime() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertEqual(item.cue(steppingFrom: 12, direction: .previous)?.time, 10)
    }

    func test_cueSteppingPrevious_returnsNilWhenPlayheadBeforeFirstCue() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertNil(item.cue(steppingFrom: 0, direction: .previous))
    }

    func test_cueSteppingPrevious_skipsCueAtExactPlayheadTime() {
        let item = makeItem(cueTimes: [5, 10, 15])
        let target = item.cue(steppingFrom: 10, direction: .previous)
        XCTAssertEqual(
            target?.time,
            5,
            "stepping back from a playhead sitting exactly on a cue must skip that cue, "
                + "otherwise repeated ↑ presses would never advance"
        )
    }

    // MARK: - .next

    func test_cueSteppingNext_returnsFirstCueStrictlyAfterCurrentTime() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertEqual(item.cue(steppingFrom: 12, direction: .next)?.time, 15)
    }

    func test_cueSteppingNext_returnsNilWhenPlayheadAtOrAfterLastCue() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertNil(item.cue(steppingFrom: 15, direction: .next), "no wrap; last cue is terminal")
        XCTAssertNil(item.cue(steppingFrom: 20, direction: .next))
    }

    func test_cueSteppingNext_skipsCueAtExactPlayheadTime() {
        let item = makeItem(cueTimes: [5, 10, 15])
        let target = item.cue(steppingFrom: 10, direction: .next)
        XCTAssertEqual(
            target?.time,
            15,
            "stepping forward from a playhead sitting exactly on a cue must skip that cue, "
                + "otherwise repeated ↓ presses would never advance"
        )
    }

    // MARK: - empty

    func test_cueStepping_emptyCues_returnsNilForBothDirections() {
        let item = makeItem(cueTimes: [])
        XCTAssertNil(item.cue(steppingFrom: 5, direction: .previous))
        XCTAssertNil(item.cue(steppingFrom: 5, direction: .next))
    }

    // MARK: - activeCue(at:)

    func test_activeCue_returnsLatestCueAtOrBeforePlayhead() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertEqual(item.activeCue(at: 12)?.time, 10)
    }

    func test_activeCue_returnsNilWhenPlayheadBeforeFirstCue() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertNil(item.activeCue(at: 0))
    }

    func test_activeCue_returnsCueAtExactPlayheadTime() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertEqual(
            item.activeCue(at: 10)?.time,
            10,
            "the cue at the exact playhead time IS the active cue (inclusive `<=`), "
                + "different from cue(steppingFrom:) which excludes the playhead cue"
        )
    }

    func test_activeCue_returnsLastCueWhenPlayheadAfterAll() {
        let item = makeItem(cueTimes: [5, 10, 15])
        XCTAssertEqual(
            item.activeCue(at: 999)?.time,
            15,
            "notes from the last cue persist past it until the show ends"
        )
    }

    func test_activeCue_emptyCues_returnsNil() {
        let item = makeItem(cueTimes: [])
        XCTAssertNil(item.activeCue(at: 5))
    }
}
