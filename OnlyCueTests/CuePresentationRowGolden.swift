import Foundation
@testable import OnlyCue

/// The row / list half of vector 8's generator, split from
/// `CuePresentationGolden` so both stay under SwiftLint's file cap.
enum CuePresentationRowGolden {

    static func sectionCountCases() -> [CuePresentationGoldenVector.SectionCountCase] {
        CuePresentationRowFixtures.sectionCounts.map {
            .init(name: $0.name, count: $0.count, expect: CueListSectionHeader.countText(for: $0.count))
        }
    }

    static func rowTapCases() -> [CuePresentationGoldenVector.RowTapIntentCase] {
        CuePresentationRowFixtures.rowTaps.map { fixture in
            let intent = CueRowTap.intent(
                target: fixture.target,
                modifier: fixture.modifier,
                isReadOnly: fixture.isReadOnly
            )
            return .init(
                name: fixture.name,
                target: fixture.target == .field ? "field" : "stripe",
                modifier: name(of: fixture.modifier),
                isReadOnly: fixture.isReadOnly,
                expect: name(of: intent)
            )
        }
    }

    static func name(of modifier: CueRowTapModifier) -> String {
        switch modifier {
        case .plain: "plain"
        case .toggle: "toggle"
        case .range: "range"
        }
    }

    private static func name(of intent: CueRowTapIntent) -> String {
        switch intent {
        case .beginEdit: "beginEdit"
        case .toggleSelection: "toggleSelection"
        case .extendRange: "extendRange"
        case .selectAndSeek: "selectAndSeek"
        case .ignored: "ignored"
        }
    }

    /// The range is emitted in displayed order so the committed JSON diffs
    /// readably, but `range(in:from:to:)` returns a *set* — the C# verifier
    /// compares it as one.
    static func rangeSelectionCases() throws -> [CuePresentationGoldenVector.RangeSelectionCase] {
        try CuePresentationRowFixtures.rangeSelections.map { fixture in
            let displayed = try fixture.displayed.map(CuePresentationGolden.uuid)
            let anchor = try fixture.anchor.map(CuePresentationGolden.uuid)
            let target = try CuePresentationGolden.uuid(fixture.target)
            let selected = CueRangeSelection.range(in: displayed, from: anchor, to: target)
            // `target` can sit outside `displayed` (the orphan case), so walk
            // the displayed order first and append anything left over.
            let ordered = displayed.filter(selected.contains)
                + selected.subtracting(displayed).sorted { $0.uuidString < $1.uuidString }
            return .init(
                name: fixture.name,
                displayed: fixture.displayed,
                anchor: fixture.anchor,
                target: fixture.target,
                expect: ordered.map(\.uuidString)
            )
        }
    }

    static func rowFillCases() -> [CuePresentationGoldenVector.RowFillCase] {
        CuePresentationRowFixtures.rowFills.map { fixture in
            .init(
                name: fixture.name,
                isSelected: fixture.isSelected,
                isCurrent: fixture.isCurrent,
                hasTint: fixture.hasTint,
                expect: CueRowFill.resolution(
                    isSelected: fixture.isSelected,
                    isCurrent: fixture.isCurrent,
                    hasTint: fixture.hasTint
                ).rawValue
            )
        }
    }

    static func goFilterCases() throws -> [CuePresentationGoldenVector.GoFilterCase] {
        let types = try [CuePresentationRowFixtures.lighting, CuePresentationRowFixtures.sound]
            .map { id in
                CuePointType(id: try CuePresentationGolden.uuid(id), name: "Type", colorHex: "#FF0000")
            }
        return CuePresentationRowFixtures.goFilters.map { fixture in
            .init(
                name: fixture.name,
                rawID: fixture.rawID,
                typeIDs: types.map(\.id.uuidString),
                isShowMode: fixture.isShowMode,
                expect: CueListGoFilter.resolve(
                    rawID: fixture.rawID,
                    types: types,
                    isShowMode: fixture.isShowMode
                )?.uuidString
            )
        }
    }

    static func rowOpacityCases() throws -> [CuePresentationGoldenVector.RowOpacityCase] {
        let dimmed = CuePresentationRowFixtures.dimmed
        return try CuePresentationRowFixtures.rowOpacities.map { fixture in
            let filter = try fixture.filter.map(CuePresentationGolden.uuid)
            return .init(
                name: fixture.name,
                cueTypeID: fixture.cueTypeID,
                filter: fixture.filter,
                dimmed: GoldenDouble(dimmed),
                expect: GoldenDouble(
                    CueListRowOpacity.value(
                        cueTypeID: try CuePresentationGolden.uuid(fixture.cueTypeID),
                        filter: filter,
                        dimmed: dimmed
                    )
                )
            )
        }
    }

    static func activeCueCases() throws -> [CuePresentationGoldenVector.ActiveCueCase] {
        let seeds = CuePresentationRowFixtures.activeCues
        let cues = try seeds.map(CuePresentationGolden.cue)
        return try CuePresentationRowFixtures.activeCueInputs.map { input in
            // `activeCue` reads only `cues`; the media reference is inert
            // scaffolding and deliberately not carried in the vector.
            let item = MediaItem(
                id: try CuePresentationGolden.uuid(CuePresentationRowFixtures.itemID),
                media: MediaReference(displayName: "song.wav", kind: .audio, duration: 120, bookmarkData: Data()),
                cues: input.useCues ? cues : []
            )
            let typeID = try input.typeID.map(CuePresentationGolden.uuid)
            return .init(
                name: input.name,
                cues: input.useCues ? seeds : [],
                currentTime: GoldenDouble(input.currentTime),
                typeID: input.typeID,
                expectCueID: item.activeCue(at: input.currentTime, typeID: typeID)?.id.uuidString
            )
        }
    }

    static func emptyStateCases() -> [CuePresentationGoldenVector.EmptyStateCase] {
        CuePresentationRowFixtures.emptyStates.map {
            .init(
                name: $0.name,
                hasActiveItem: $0.hasActiveItem,
                expect: CueListEmptyState.message(hasActiveItem: $0.hasActiveItem)
            )
        }
    }
}
