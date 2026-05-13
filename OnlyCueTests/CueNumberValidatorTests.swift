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
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: 2.0)
        let c = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: nil, for: target.id, in: [a, target, c]), .ok)
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
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.0, for: target.id, in: [a, target]), .duplicate)
    }

    func test_committingOwnNumberToItself_isOk() {
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: 2.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 2.0, for: target.id, in: [a, target]), .ok)
    }

    // MARK: - strictly ascending by time

    func test_strictAscending_validBetween() {
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: 2.0)
        let c = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.5, for: target.id, in: [a, target, c]), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 2.5, for: target.id, in: [a, target, c]), .ok)
    }

    func test_strictAscending_belowLowerBound_rejected() {
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        let c = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 0.5, for: target.id, in: [a, target, c]),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 3.0)
        )
    }

    func test_strictAscending_aboveUpperBound_rejected() {
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        let c = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 3.5, for: target.id, in: [a, target, c]),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 3.0)
        )
    }

    func test_strictAscending_equalToNeighborIsDuplicateNotOutOfRange() {
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        let c = cue(time: 3.0, number: 3.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.0, for: target.id, in: [a, target, c]), .duplicate)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 3.0, for: target.id, in: [a, target, c]), .duplicate)
    }

    // MARK: - unnumbered neighbors are skipped

    func test_unnumberedNeighbors_areSkipped() {
        // cues at t=1..4 with numbers [1, nil, nil, 2]. Editing t=2 or t=3
        // must require strictly between 1 and 2.
        let a = cue(time: 1.0, number: 1.0)
        let mid1 = cue(time: 2.0, number: nil)
        let mid2 = cue(time: 3.0, number: nil)
        let d = cue(time: 4.0, number: 2.0)
        let cues = [a, mid1, mid2, d]
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.5, for: mid1.id, in: cues), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.75, for: mid2.id, in: cues), .ok)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 0.9, for: mid1.id, in: cues),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 2.0)
        )
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 2.5, for: mid2.id, in: cues),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: 2.0)
        )
    }

    // MARK: - half-open bounds

    func test_earliestInTime_onlyUpperBoundApplies() {
        let target = cue(time: 1.0, number: nil)
        let c = cue(time: 2.0, number: 2.0)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 0.5, for: target.id, in: [target, c]), .ok)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 2.5, for: target.id, in: [target, c]),
            .outOfRange(lowerExclusive: nil, upperExclusive: 2.0)
        )
    }

    func test_latestInTime_onlyLowerBoundApplies() {
        let a = cue(time: 1.0, number: 1.0)
        let target = cue(time: 2.0, number: nil)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 1.5, for: target.id, in: [a, target]), .ok)
        XCTAssertEqual(CueNumberValidator.validate(candidate: 5.0, for: target.id, in: [a, target]), .ok)
        XCTAssertEqual(
            CueNumberValidator.validate(candidate: 0.5, for: target.id, in: [a, target]),
            .outOfRange(lowerExclusive: 1.0, upperExclusive: nil)
        )
    }
}
