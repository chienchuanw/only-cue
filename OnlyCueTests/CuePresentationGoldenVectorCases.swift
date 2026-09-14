import Foundation

/// The case shapes for `CuePresentationGoldenVector`, mirrored one-for-one by
/// the C# verifier's DTOs in `windows/OnlyCue.Core.Tests/CuePresentationVector.cs`.
///
/// Every `name` is the C# `[MemberData]` key, so they must be unique within a
/// group — `test_caseNamesAreUnique` enforces that, because a collision would
/// silently drop a case rather than fail.
extension CuePresentationGoldenVector {

    /// A cue reduced to the fields the presentation layer actually reads.
    /// Deliberately not the whole `Cue`: a vector that carried `notes` or
    /// `fadeTime` would invite a reviewer to think those participate in the
    /// decision, and would churn whenever the document schema moves.
    struct CueFixture: Codable, Equatable {
        let id: String
        let typeID: String
        let time: GoldenDouble
        /// Absent means *unnumbered*, which is a real state — not a gap in the
        /// fixture (#830).
        let cueNumber: GoldenDouble?
    }

    struct FadeParseCase: Codable, Equatable {
        let name: String
        let input: String
        /// Both absent = the string is rejected. `FadeTime.parse` returns an
        /// optional whole, never a half-parsed pair.
        let expectFadeIn: GoldenDouble?
        let expectFadeOut: GoldenDouble?
    }

    struct FadeFormatCase: Codable, Equatable {
        let name: String
        let fadeIn: GoldenDouble
        let fadeOut: GoldenDouble
        let expectFormat: String
        /// `cellDisplay` blanks a zero fade where `format` spells `"0"` (#804),
        /// so both are pinned — one is not derivable from the other.
        let expectCellDisplay: String
    }

    /// `kind` is the case name of `CueNumberValidator.Result`; the two bounds are
    /// present only for `outOfRange`, and each is independently optional because
    /// a cue at either end of the list has no neighbour on that side.
    struct ValidationResult: Codable, Equatable {
        let kind: String
        let lowerExclusive: GoldenDouble?
        let upperExclusive: GoldenDouble?
    }

    struct CueNumberValidationCase: Codable, Equatable {
        let name: String
        let cues: [CueFixture]
        let targetID: String
        /// Absent = clearing the number, which is always allowed.
        let candidate: GoldenDouble?
        let expect: ValidationResult
    }

    struct CueNumberErrorCase: Codable, Equatable {
        let name: String
        let result: ValidationResult
        /// Absent for `.ok`. Otherwise byte-exact — `invalidFormat` contains
        /// U+2013 EN DASH, not a hyphen, and that is the point of the group.
        let expect: String?
    }

    struct SectionCountCase: Codable, Equatable {
        let name: String
        let count: Int
        let expect: String
    }

    struct RowTapIntentCase: Codable, Equatable {
        let name: String
        let target: String
        let isExtending: Bool
        let isReadOnly: Bool
        let expect: String
    }

    struct RowFillCase: Codable, Equatable {
        let name: String
        let isSelected: Bool
        let isCurrent: Bool
        let hasTint: Bool
        let expect: String
    }

    struct GoFilterCase: Codable, Equatable {
        let name: String
        let rawID: String
        let typeIDs: [String]
        let isShowMode: Bool
        /// Absent = All cues.
        let expect: String?
    }

    struct RowOpacityCase: Codable, Equatable {
        let name: String
        let cueTypeID: String
        let filter: String?
        let dimmed: GoldenDouble
        let expect: GoldenDouble
    }

    struct ActiveCueCase: Codable, Equatable {
        let name: String
        let cues: [CueFixture]
        let currentTime: GoldenDouble
        let typeID: String?
        /// Absent = no cue is active, which happens before the first cue and on
        /// an empty list.
        let expectCueID: String?
    }

    struct EmptyStateCase: Codable, Equatable {
        let name: String
        let hasActiveItem: Bool
        let expect: String
    }
}
