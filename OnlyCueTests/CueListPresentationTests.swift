import XCTest
import SwiftUI
@testable import OnlyCue

/// The four presentation decisions that used to live inline inside SwiftUI view
/// properties (`CueListPane+RowBackground.swift`, `CueListPane.emptyState`),
/// extracted so golden vector 8 can pin them for the Windows port (#837, D3).
///
/// These tests are the extraction's own contract. The *regression* harness is
/// the untouched suite around them — `CueRowFillTests`, the Show-mode suites and
/// the cue-list XCUITests all keep passing without edits, which is what proves
/// the lift was behaviour-preserving.
final class CueListPresentationTests: XCTestCase {

    // MARK: - CueRowFill.Resolution

    /// The branch, not the `Color`. A `Color` comparison cannot tell "fell back
    /// to the achromatic selection fill" from "the playhead is here" — both
    /// return `selection` — so the C# mirror could invert the precedence and
    /// still match a colour-level vector.
    func test_resolution_namesTheBranch_notTheColor() {
        XCTAssertEqual(
            CueRowFill.resolution(isSelected: false, isCurrent: false, hasTint: true),
            .clear
        )
        XCTAssertEqual(
            CueRowFill.resolution(isSelected: true, isCurrent: false, hasTint: true),
            .tint
        )
        XCTAssertEqual(
            CueRowFill.resolution(isSelected: true, isCurrent: false, hasTint: false),
            .selectionFallback
        )
        XCTAssertEqual(
            CueRowFill.resolution(isSelected: false, isCurrent: true, hasTint: true),
            .current
        )
    }

    /// `isCurrent` is tested before `isSelected` (#671). Both `.current` and
    /// `.selectionFallback` paint `selection`, so only the resolution
    /// distinguishes a wrong branch order.
    func test_resolution_currentWinsOverSelected() {
        XCTAssertEqual(
            CueRowFill.resolution(isSelected: true, isCurrent: true, hasTint: true),
            .current
        )
        XCTAssertEqual(
            CueRowFill.resolution(isSelected: true, isCurrent: true, hasTint: false),
            .current
        )
    }

    /// An unselected row is clear whether or not it has a tint — the tint is the
    /// *selected* row's chroma, not a per-row decoration (Figma `318:1228`).
    func test_resolution_unselectedIsClearRegardlessOfTint() {
        XCTAssertEqual(
            CueRowFill.resolution(isSelected: false, isCurrent: false, hasTint: false),
            .clear
        )
    }

    /// `color` must stay a pure rendering of `resolution`, or the vector pins
    /// one thing and the app draws another.
    func test_color_agreesWithResolution() {
        let tint = Color.red
        let selection = Color.gray
        for isSelected in [false, true] {
            for isCurrent in [false, true] {
                for hasTint in [false, true] {
                    let resolved = CueRowFill.resolution(
                        isSelected: isSelected,
                        isCurrent: isCurrent,
                        hasTint: hasTint
                    )
                    let expected: Color
                    switch resolved {
                    case .current, .selectionFallback: expected = selection
                    case .tint: expected = tint
                    case .clear: expected = .clear
                    }
                    XCTAssertEqual(
                        CueRowFill.color(
                            isSelected: isSelected,
                            isCurrent: isCurrent,
                            tint: hasTint ? tint : nil,
                            selection: selection
                        ),
                        expected,
                        "isSelected: \(isSelected), isCurrent: \(isCurrent), hasTint: \(hasTint)"
                    )
                }
            }
        }
    }

    // MARK: - CueListGoFilter

    /// Fixed ids, so a failure message names the same value on every run.
    private static let liveID = "11111111-1111-1111-1111-111111111111"
    private static let otherID = "33333333-3333-3333-3333-333333333333"

    private func liveType() throws -> CuePointType {
        CuePointType(id: try XCTUnwrap(UUID(uuidString: Self.liveID)), name: "Lighting", colorHex: "#FF0000")
    }

    /// The filter only exists in Show mode (#657): the stored id is per-window
    /// scene state and survives a mode switch, so it must be gated on the mode
    /// rather than on the id being present.
    func test_goFilter_isNilOutsideShowMode() throws {
        let type = try liveType()
        XCTAssertNil(
            CueListGoFilter.resolve(rawID: Self.liveID, types: [type], isShowMode: false)
        )
    }

    func test_goFilter_resolvesALiveType() throws {
        let type = try liveType()
        XCTAssertEqual(
            CueListGoFilter.resolve(rawID: Self.liveID, types: [type], isShowMode: true),
            type.id
        )
    }

    /// "" is the `@SceneStorage` default and means All cues — never a filter.
    func test_goFilter_emptyRawIDReadsAsAllCues() throws {
        XCTAssertNil(CueListGoFilter.resolve(rawID: "", types: [try liveType()], isShowMode: true))
    }

    /// A syntactically valid id for a type that has since been deleted also
    /// reads as All, rather than filtering the list down to nothing.
    func test_goFilter_deletedTypeReadsAsAllCues() throws {
        XCTAssertNil(
            CueListGoFilter.resolve(
                rawID: "22222222-2222-2222-2222-222222222222",
                types: [try liveType()],
                isShowMode: true
            )
        )
    }

    func test_goFilter_malformedRawIDReadsAsAllCues() throws {
        XCTAssertNil(
            CueListGoFilter.resolve(rawID: "not-a-uuid", types: [try liveType()], isShowMode: true)
        )
    }

    // MARK: - CueListRowOpacity

    /// No filter → every row is full strength, in any mode.
    func test_rowOpacity_isFullWhenNoFilterIsActive() throws {
        XCTAssertEqual(
            CueListRowOpacity.value(cueTypeID: try liveType().id, filter: nil, dimmed: 0.35),
            1
        )
    }

    func test_rowOpacity_isFullForTheFilteredType() throws {
        let id = try liveType().id
        XCTAssertEqual(CueListRowOpacity.value(cueTypeID: id, filter: id, dimmed: 0.35), 1)
    }

    /// Other types dim rather than disappear (#657) — the walked type stands out
    /// but the surrounding cues stay readable.
    func test_rowOpacity_dimsOtherTypes() throws {
        XCTAssertEqual(
            CueListRowOpacity.value(
                cueTypeID: try XCTUnwrap(UUID(uuidString: Self.otherID)),
                filter: try liveType().id,
                dimmed: 0.35
            ),
            0.35
        )
    }

    // MARK: - CueListEmptyState

    /// Two different dead ends need two different instructions: with no media
    /// there is nothing to place a cue against, so "press M" would be a lie.
    func test_emptyState_asksForMediaWhenThereIsNoActiveItem() {
        XCTAssertEqual(
            CueListEmptyState.message(hasActiveItem: false),
            "Import a media file to start adding cues."
        )
    }

    func test_emptyState_asksForACueWhenMediaIsLoaded() {
        XCTAssertEqual(
            CueListEmptyState.message(hasActiveItem: true),
            "Press M to add a cue at the playhead."
        )
    }
}
