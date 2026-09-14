import Foundation
@testable import OnlyCue

/// Inputs for vector 8's two cue-number groups.
///
/// Ids are fixed literals, never `UUID()` — a generated id would make the
/// committed vector churn on every run and the drift guard useless.
enum CuePresentationCueNumberFixtures {

    static let lighting = "00000000-0000-0000-0000-0000000000a1"
    static let sound = "00000000-0000-0000-0000-0000000000a2"

    static let cueA = "00000000-0000-0000-0000-0000000000c1"
    static let cueB = "00000000-0000-0000-0000-0000000000c2"
    static let cueC = "00000000-0000-0000-0000-0000000000c3"
    static let cueD = "00000000-0000-0000-0000-0000000000c4"
    static let absent = "00000000-0000-0000-0000-0000000000ff"

    /// Four cues in time order, numbered 1 / 2 / 3, plus an unnumbered one at the
    /// end. The unnumbered cue is load-bearing: the neighbour lookup
    /// `compactMap`s the numbers away, so a port that treated a missing number as
    /// zero would make it the lower bound for everything after it.
    static let cues: [CuePresentationCueSeed] = [
        .init(id: cueA, typeID: lighting, time: 0, cueNumber: 1),
        .init(id: cueB, typeID: lighting, time: 10, cueNumber: 2),
        .init(id: cueC, typeID: sound, time: 20, cueNumber: 3),
        .init(id: cueD, typeID: lighting, time: 30, cueNumber: nil)
    ]

    /// Candidates fed to `CueNumberValidator.validate` against `cues`.
    ///
    /// The ordering of the checks is itself the contract — format, then
    /// duplicate, then neighbour range — so each case is chosen to fail exactly
    /// one of them, and "a duplicate that is also out of range" pins that the
    /// duplicate answer wins.
    static let validationInputs: [CuePresentationValidationInput] = [
        .init(name: "clearing the number is always allowed", targetID: cueB, candidate: nil),
        .init(name: "a number between both neighbours is accepted", targetID: cueB, candidate: 1.5),
        .init(name: "committing a cue's own number back to itself is accepted", targetID: cueB, candidate: 2),
        .init(name: "three decimal places are accepted", targetID: cueB, candidate: 1.125),
        .init(name: "a number already in use is a duplicate", targetID: cueB, candidate: 3),
        .init(name: "a duplicate that is also out of range still reads as a duplicate",
              targetID: cueB,
              candidate: 1),
        .init(name: "at or below the previous neighbour is out of range", targetID: cueB, candidate: 0.5),
        .init(name: "at or above the next neighbour is out of range", targetID: cueB, candidate: 3.5),
        .init(name: "the first cue has no lower bound", targetID: cueA, candidate: 0.001),
        .init(name: "the first cue is still bounded above", targetID: cueA, candidate: 2.5),
        .init(name: "the last numbered cue has no upper bound", targetID: cueC, candidate: 9999.999),
        .init(name: "the last numbered cue is still bounded below", targetID: cueC, candidate: 1.5),
        .init(name: "an unnumbered cue takes its bounds from the numbered neighbours",
              targetID: cueD,
              candidate: 5),
        .init(name: "a cue id not in the list is validated on format and duplicates only",
              targetID: absent,
              candidate: 5),
        .init(name: "below the numbering minimum is a format error", targetID: cueB, candidate: 0.0005),
        .init(name: "zero is a format error", targetID: cueB, candidate: 0),
        .init(name: "a negative number is a format error", targetID: cueB, candidate: -1.5),
        .init(name: "above the numbering maximum is a format error", targetID: cueB, candidate: 10_000),
        .init(name: "a fourth decimal place is a format error", targetID: cueB, candidate: 1.0005),
        .init(name: "not-a-number is a format error", targetID: cueB, candidate: Double.nan),
        .init(name: "infinity is a format error", targetID: cueB, candidate: Double.infinity)
    ]

    /// Results fed to `CueNumberErrorMessage.text`. Spelled directly rather than
    /// harvested from the validator so a result the validator cannot currently
    /// produce — `outOfRange` with both bounds nil — is still pinned; the helper
    /// has a branch for it and an unpinned branch is where a port diverges.
    static let errorInputs: [(name: String, result: CueNumberValidator.Result)] = [
        ("a valid number has no message", .ok),
        ("the format message names both bounds and the decimal limit", .invalidFormat),
        ("the duplicate message", .duplicate),
        ("both neighbours present", .outOfRange(lowerExclusive: 1, upperExclusive: 3)),
        ("only a lower neighbour", .outOfRange(lowerExclusive: 1, upperExclusive: nil)),
        ("only an upper neighbour", .outOfRange(lowerExclusive: nil, upperExclusive: 3)),
        ("decimal bounds keep their own spelling",
         .outOfRange(lowerExclusive: 1.5, upperExclusive: 2.25)),
        ("neither neighbour falls back to the format message",
         .outOfRange(lowerExclusive: nil, upperExclusive: nil))
    ]
}
