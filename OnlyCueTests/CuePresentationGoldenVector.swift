import Foundation

/// The cross-platform golden-vector contract for the cue list's **presentation**
/// layer (epic #728, M1d — vector 8, specified in
/// `docs/superpowers/specs/2026-09-14-windows-m1d-cue-presentation.md`).
///
/// macOS is the source of truth: `CuePresentationGolden` emits
/// `golden/cue-presentation-v1.json` from the Swift implementations, and the C#
/// `OnlyCue.Core` re-implementation must reproduce every case (verified on
/// Windows CI).
///
/// Unlike vectors 1–7 this one pins *decisions*, not bytes on a wire. That makes
/// the failure mode quieter — a wrong branch renders a plausible cue list rather
/// than a malformed payload — which is exactly why it is pinned. Four of the
/// groups did not exist as callable functions until #837 extracted them out of
/// SwiftUI view properties.
///
/// The case structs live in `CuePresentationGoldenVectorCases.swift` (an
/// extension, so this type body stays under SwiftLint's cap) and the inputs in
/// the `CuePresentationGoldenFixtures*` files.
struct CuePresentationGoldenVector: Codable, Equatable {

    let contract: String   // "cue-presentation"
    let version: Int       // 1
    let note: String

    /// `FadeTime.parse` — the accept/reject grammar, including four confirmed
    /// Swift/.NET divergences a naive port gets wrong in a way that still looks
    /// like it works.
    let fadeParse: [FadeParseCase]
    /// `FadeTime.format` / `.cellDisplay`.
    let fadeFormat: [FadeFormatCase]
    /// `CueNumberValidator.validate` — the four results and both bounds.
    let cueNumberValidation: [CueNumberValidationCase]
    /// `CueNumberErrorMessage.text` — the user-facing strings, byte for byte.
    let cueNumberErrors: [CueNumberErrorCase]
    /// `CueListSectionHeader.countText`.
    let sectionCount: [SectionCountCase]
    /// `CueRowTap.intent`.
    let rowTapIntent: [RowTapIntentCase]
    /// `CueRangeSelection.range(in:from:to:)` — the ⇧-click range (#790).
    let rangeSelection: [RangeSelectionCase]
    /// `CueRowFill.resolution` — the branch, never the `Color`.
    let rowFill: [RowFillCase]
    /// `CueListGoFilter.resolve`.
    let goFilter: [GoFilterCase]
    /// `CueListRowOpacity.value`.
    let rowOpacity: [RowOpacityCase]
    /// `MediaItem.activeCue(at:typeID:)`.
    let activeCue: [ActiveCueCase]
    /// `CueListEmptyState.message`.
    let emptyState: [EmptyStateCase]
}
