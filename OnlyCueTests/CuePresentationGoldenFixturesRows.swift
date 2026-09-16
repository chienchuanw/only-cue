import Foundation
@testable import OnlyCue

/// Inputs for vector 8's seven row / list groups. The three boolean groups are
/// exhaustive over their input space rather than sampled — each is small enough
/// that "we picked the interesting ones" would be a worse contract than "all of
/// them".
enum CuePresentationRowFixtures {

    static let lighting = CuePresentationCueNumberFixtures.lighting
    static let sound = CuePresentationCueNumberFixtures.sound
    /// A type id that is syntactically valid but names nothing in the document.
    static let deleted = "00000000-0000-0000-0000-0000000000dd"
    /// Scaffolding for the `activeCue` group's host item — never pinned.
    static let itemID = "00000000-0000-0000-0000-0000000000e1"

    static let sectionCounts: [(name: String, count: Int)] = [
        ("zero is plural", 0),
        ("one is singular", 1),
        ("two is plural", 2),
        ("large counts stay plural", 42)
    ]

    /// All twelve combinations, collapsing to the five intents. The stripe ignores
    /// `isReadOnly` because it is the only way left to jump the playhead from the
    /// cue list in Show mode, where the columns are `.disabled` (#786) — so a
    /// read-only stripe tap still seeks where a read-only field tap is `ignored`.
    ///
    /// Eight until #790 split ⌘ from ⇧: collapsing them into one `isExtending`
    /// flag is exactly the bug that vector would have frozen as correct.
    static let rowTaps: [CuePresentationRowTapInput] =
        [CueRowTapTarget.field, .stripe].flatMap { target in
            CueRowTapModifier.allCases.flatMap { modifier in
                [false, true].map { isReadOnly in
                    CuePresentationRowTapInput(
                        name: "\(target == .field ? "field" : "stripe"), "
                            + "modifier=\(CuePresentationRowGolden.name(of: modifier)), "
                            + "readOnly=\(isReadOnly)",
                        target: target,
                        modifier: modifier,
                        isReadOnly: isReadOnly
                    )
                }
            }
        }

    /// Ten rows in displayed order. Deliberately *not* in ascending id order:
    /// `rangeSelections` below ranges across `shuffled`, and if the range ever
    /// started sorting ids instead of following the array, an ascending seed
    /// would hide it.
    static let rangeRows: [String] = (0..<10).map {
        String(format: "00000000-0000-0000-0000-0000000007%02x", 9 - $0)
    }

    /// The same rows in an order that has nothing to do with the array above —
    /// stands in for a filtered / reordered list.
    static let rangeShuffled: [String] = [7, 1, 9, 3, 0].map { rangeRows[$0] }

    /// A row id that is syntactically valid but is not displayed — a stale
    /// anchor (filtered out, or deleted from another pane) or a target the
    /// caller could not really have clicked.
    static let rangeOrphan = "00000000-0000-0000-0000-0000000007ff"

    static let rangeSelections: [CuePresentationRangeSelectionInput] = [
        .init(
            name: "a forward range includes both ends",
            displayed: rangeRows,
            anchor: rangeRows[2],
            target: rangeRows[8]
        ),
        .init(
            name: "a backward range covers the same rows",
            displayed: rangeRows,
            anchor: rangeRows[8],
            target: rangeRows[2]
        ),
        .init(
            name: "anchor equals target selects that one row",
            displayed: rangeRows,
            anchor: rangeRows[4],
            target: rangeRows[4]
        ),
        .init(
            name: "without an anchor only the clicked row is selected",
            displayed: rangeRows,
            anchor: nil,
            target: rangeRows[6]
        ),
        .init(
            name: "an anchor no longer displayed selects only the clicked row",
            displayed: rangeRows,
            anchor: rangeOrphan,
            target: rangeRows[6]
        ),
        .init(
            name: "a target not displayed still selects the clicked row",
            displayed: rangeRows,
            anchor: rangeRows[1],
            target: rangeOrphan
        ),
        .init(
            name: "the range follows displayed order, not id order",
            displayed: rangeShuffled,
            anchor: rangeShuffled[1],
            target: rangeShuffled[3]
        ),
        .init(
            name: "an empty list selects only the clicked row",
            displayed: [],
            anchor: nil,
            target: rangeOrphan
        )
    ]

    /// All eight combinations, so the `isCurrent`-before-`isSelected` precedence
    /// is pinned from every direction (#671).
    static let rowFills: [CuePresentationRowFillInput] =
        [false, true].flatMap { isSelected in
            [false, true].flatMap { isCurrent in
                [false, true].map { hasTint in
                    CuePresentationRowFillInput(
                        name: "selected=\(isSelected), current=\(isCurrent), tint=\(hasTint)",
                        isSelected: isSelected,
                        isCurrent: isCurrent,
                        hasTint: hasTint
                    )
                }
            }
        }

    /// `UUID(uuidString:)` is stricter than .NET's `Guid.TryParse`, which is the
    /// hazard this group exists for: `Guid.TryParse` accepts braced, parenthesised
    /// and dash-less spellings that Swift rejects outright. A port using
    /// `Guid.TryParse` would resolve a filter from a string macOS reads as
    /// "All cues" — the two platforms would then walk different cues from the
    /// same scene storage.
    static let goFilters: [CuePresentationGoFilterInput] = [
        .init(name: "a live type id in Show mode resolves", rawID: lighting, isShowMode: true),
        .init(name: "the same id outside Show mode reads as All cues", rawID: lighting, isShowMode: false),
        .init(name: "the scene-storage default reads as All cues", rawID: "", isShowMode: true),
        .init(name: "a deleted type reads as All cues", rawID: deleted, isShowMode: true),
        .init(name: "a malformed id reads as All cues", rawID: "not-a-uuid", isShowMode: true),
        .init(name: "an uppercase id resolves", rawID: lighting.uppercased(), isShowMode: true),
        .init(name: "a braced id is rejected", rawID: "{\(lighting)}", isShowMode: true),
        .init(name: "a parenthesised id is rejected", rawID: "(\(lighting))", isShowMode: true),
        .init(name: "a dash-less id is rejected",
              rawID: lighting.replacingOccurrences(of: "-", with: ""),
              isShowMode: true)
    ]

    /// `CueListLayout.dimmedRowOpacity` at the time of writing. Seated as a
    /// literal rather than read from the layout constant: the vector pins the
    /// *rule* (which rows dim), and a future visual tweak to the constant should
    /// not read as a cross-platform contract break.
    static let dimmed: Double = 0.35

    static let rowOpacities: [CuePresentationRowOpacityInput] = [
        .init(name: "no filter leaves every row at full strength", cueTypeID: lighting, filter: nil),
        .init(name: "the filtered type stays at full strength", cueTypeID: lighting, filter: lighting),
        .init(name: "another type dims", cueTypeID: sound, filter: lighting)
    ]

    /// Cues at 0 / 10 / 20 across two types, plus a pair sharing a time.
    ///
    /// The tie at 20 is the point: Swift's `max(by:)` and .NET's `MaxBy` both
    /// return the **first** extremal element (measured, not assumed), so a port
    /// that reached for last-wins would pick the other cue. That is a different
    /// mechanism from #834's unstable sort, and this is where it would show.
    static let activeCues: [CuePresentationCueSeed] = [
        .init(id: CuePresentationCueNumberFixtures.cueA, typeID: lighting, time: 0, cueNumber: 1),
        .init(id: CuePresentationCueNumberFixtures.cueB, typeID: sound, time: 10, cueNumber: 2),
        .init(id: CuePresentationCueNumberFixtures.cueC, typeID: lighting, time: 20, cueNumber: 3),
        .init(id: CuePresentationCueNumberFixtures.cueD, typeID: sound, time: 20, cueNumber: 4)
    ]

    static let activeCueInputs: [CuePresentationActiveCueInput] = [
        .init(name: "before the first cue nothing is active", currentTime: -1, typeID: nil, useCues: true),
        .init(name: "exactly on a cue that cue is active", currentTime: 10, typeID: nil, useCues: true),
        .init(name: "between cues the earlier one stays active", currentTime: 15, typeID: nil, useCues: true),
        .init(name: "on a tie the first cue in list order wins", currentTime: 20, typeID: nil, useCues: true),
        .init(name: "past the last cue it stays active", currentTime: 100, typeID: nil, useCues: true),
        .init(name: "at time zero the cue at zero is active", currentTime: 0, typeID: nil, useCues: true),
        .init(name: "the type filter picks the latest cue of that type",
              currentTime: 25,
              typeID: lighting,
              useCues: true),
        .init(name: "the type filter ignores a later cue of another type",
              currentTime: 15,
              typeID: lighting,
              useCues: true),
        .init(name: "a type with no cue before the playhead yields nothing",
              currentTime: 5,
              typeID: sound,
              useCues: true),
        .init(name: "a type absent from the list yields nothing",
              currentTime: 100,
              typeID: deleted,
              useCues: true),
        .init(name: "an empty cue list yields nothing", currentTime: 100, typeID: nil, useCues: false)
    ]

    static let emptyStates: [(name: String, hasActiveItem: Bool)] = [
        ("with no media loaded the copy asks for an import", false),
        ("with media loaded the copy asks for a cue", true)
    ]
}
