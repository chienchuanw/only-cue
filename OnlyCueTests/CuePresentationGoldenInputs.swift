import Foundation
@testable import OnlyCue

/// Input shapes for vector 8's fixtures.
///
/// These are plain structs rather than tuples because SwiftLint's `large_tuple`
/// rule caps tuples at two members — and the rule is right here: `(name,
/// isSelected, isCurrent, hasTint)` is unreadable at the call site, where three
/// adjacent `Bool`s are exactly the kind of thing that silently swaps.
///
/// They carry *inputs only*. Every expectation is produced by running the Swift
/// implementation; see `CuePresentationGolden`.

/// A cue seed is the vector's own `CueFixture` — the fixtures and the committed
/// JSON are then the same values by construction, so the two cannot drift apart.
typealias CuePresentationCueSeed = CuePresentationGoldenVector.CueFixture

struct CuePresentationFormatInput {
    let name: String
    let fadeIn: TimeInterval
    let fadeOut: TimeInterval
}

struct CuePresentationValidationInput {
    let name: String
    let targetID: String
    /// Absent = clearing the number.
    let candidate: Double?
}

struct CuePresentationRowTapInput {
    let name: String
    let target: CueRowTapTarget
    let modifier: CueRowTapModifier
    let isReadOnly: Bool
}

struct CuePresentationRangeSelectionInput {
    let name: String
    let displayed: [String]
    /// Absent = no row has been selected without ⇧ yet.
    let anchor: String?
    let target: String
}

struct CuePresentationRowFillInput {
    let name: String
    let isSelected: Bool
    let isCurrent: Bool
    let hasTint: Bool
}

struct CuePresentationGoFilterInput {
    let name: String
    let rawID: String
    let isShowMode: Bool
}

struct CuePresentationRowOpacityInput {
    let name: String
    let cueTypeID: String
    /// Absent = All cues.
    let filter: String?
}

struct CuePresentationActiveCueInput {
    let name: String
    let currentTime: TimeInterval
    let typeID: String?
    /// `false` seeds an empty cue list, which is its own branch.
    let useCues: Bool
}
