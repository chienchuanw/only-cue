import XCTest
@testable import OnlyCue

/// Pure validator for cue-number assignments. Mirrors the grandMA2 rules
/// enforced at edit time: format (0.001–9999.999, ≤3 decimals), uniqueness
/// within the active item, strictly-ascending vs immediate numbered
/// time-neighbors (unnumbered cues skipped, missing neighbor → open bound).
final class CueNumberValidatorTests: XCTestCase {

    // MARK: - Test helpers

    private static let typeID = UUID()

    private func cue(id: UUID = UUID(), time: TimeInterval, number: Double?) -> Cue {
        Cue(
            id: id,
            typeID: Self.typeID,
            cueNumber: number,
            name: "Cue",
            time: time,
            notes: "",
            fadeTime: .zero
        )
    }

    // MARK: - nil

    func test_nilIsAlwaysOk_emptyList() {
        let target = cue(time: 1.0, number: nil)
        XCTAssertEqual(CueNumberValidator.validate(candidate: nil, for: target.id, in: [target]), .ok)
    }

    func test_nilIsAlwaysOk_withSiblings() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: 2.0)
        let late = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: nil, for: target.id, in: [early, target, late]), .ok)
    }

    // MARK: - format

    func test_formatEdges() {
        let target = cue(time: 1.0, number: nil)
        let single = [target]
        XCTAssertEqual(CueNumberValidator.validate(candidate: 0.0009, for: target.id, in: single), .invalidFormat)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 0.001, for: target.id, in: single), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 9999.999, for: target.id, in: single), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 10000, for: target.id, in: single), .invalidFormat)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.0001, for: target.id, in: single), .invalidFormat)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.5, for: target.id, in: single), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 0, for: target.id, in: single), .invalidFormat)
        XCTAssertEqual(CueNumberValidator.validate(candidate: -1, for: target.id, in: single), .invalidFormat)
        XCTAssertEqual(CueNumberValidator.validate(candidate: .nan, for: target.id, in: single), .invalidFormat)
        XCTAssertEqual(CueNumberValidator.validate(candidate: .infinity, for: target.id, in: single), .invalidFormat)
    }

    // MARK: - uniqueness

    func test_duplicate_isRejected() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.0, for: target.id, in: [early, target]), .duplicate)
    }

    func test_committingOwnNumberToItself_isOk() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: 2.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 2.0, for: target.id, in: [early, target]), .ok)
    }

    // MARK: - strictly ascending by time

    func test_strictAscending_validBetween() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: 2.0)
        let late = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.5, for: target.id, in: [early, target, late]), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 2.5, for: target.id, in: [early, target, late]), .ok)
    }

    func test_strictAscending_belowLowerBound_rejected() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        let late = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 0.5, for: target.id, in: [early, target, late]),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 3.0)
        )
    }

    func test_strictAscending_aboveUpperBound_rejected() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        let late = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 3.5, for: target.id, in: [early, target, late]),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 3.0)
        )
    }

    func test_strictAscending_equalToNeighborIsDuplicateNotOutOfRange() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        let late = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.0, for: target.id, in: [early, target, late]), .duplicate)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 3.0, for: target.id, in: [early, target, late]), .duplicate)
    }

    // MARK: - unnumbered neighbors are skipped

    func test_unnumberedNeighbors_areSkipped() {
        // cues at t=1..4 with numbers [1, nil, nil, 2]. Editing t=2 or t=3
        // must require strictly between 1 and 2.
        let early = cue(time: 1.0, number: 1.0)
        let middleA = cue(time: 2.0, number: nil)
        let middleB = cue(time: 3.0, number: nil)
        let late = cue(time: 4.0, number: 2.0)
        let cues = [early, middleA, middleB, late]
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.5, for: middleA.id, in: cues), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.75, for: middleB.id, in: cues), .ok)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 0.9, for: middleA.id, in: cues),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 2.0)
        )
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 2.5, for: middleB.id, in: cues),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 2.0)
        )
    }

    // MARK: - half-open bounds

    func test_earliestInTime_onlyUpperBoundApplies() {
        let target = cue(time: 1.0, number: nil)
        let late = cue(time: 2.0, number: 2.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 0.5, for: target.id, in: [target, late]), .ok)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 2.5, for: target.id, in: [target, late]),
            .outOfRange(lowerExclusive: nil, upperExclusive: 2.0)
        )
    }

    func test_latestInTime_onlyLowerBoundApplies() {
        let early = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.5, for: target.id, in: [early, target]), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 5.0, for: target.id, in: [early, target]), .ok)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 0.5, for: target.id, in: [early, target]),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: nil)
        )
    }
}
