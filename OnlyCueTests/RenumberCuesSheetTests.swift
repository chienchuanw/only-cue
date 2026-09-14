import XCTest
import SwiftUI
@testable import OnlyCue

/// #830: the sheet's `TextField`s are unconstrained — each `Stepper(in:)` binds
/// only its own buttons — so a typed start or interval can walk the run outside
/// grandMA2's numbering domain. `CueCommands.renumberSelected` rejects such a
/// run whole, and the button is gated on the same rule so the rejection shows up
/// as a disabled control instead of a click that silently does nothing.
///
/// The sheet seeds `@State` from `initialStart` / `initialInterval`, so these
/// pass the value under test that way (see `CueNotesSheetTests`).
@MainActor
final class RenumberCuesSheetTests: XCTestCase {

    private func sheet(cueCount: Int = 3, start: Double, interval: Double = 1) -> RenumberCuesSheet {
        RenumberCuesSheet(
            cueCount: cueCount,
            initialStart: start,
            initialInterval: interval,
            onRenumber: { _, _ in },
            onCancel: {}
        )
    }

    func test_canRenumber_forAnOrdinaryRun() {
        XCTAssertTrue(sheet(start: 1).canRenumber)
    }

    func test_cannotRenumber_fromANegativeStart() {
        XCTAssertFalse(sheet(start: -1.5).canRenumber)
    }

    func test_cannotRenumber_fromZero() {
        // MA2 numbering starts at 0.001, so zero is below the domain.
        XCTAssertFalse(sheet(start: 0).canRenumber)
    }

    // An in-range start is not enough: the run walks to
    // start + (cueCount - 1) * interval, which can overrun the maximum.
    func test_cannotRenumber_whenTheRunOverrunsTheMaximum() {
        XCTAssertFalse(sheet(cueCount: 3, start: 9999, interval: 1).canRenumber)
    }

    func test_cannotRenumber_fromANegativeInterval_thatWalksBelowTheMinimum() {
        XCTAssertFalse(sheet(cueCount: 3, start: 1, interval: -1).canRenumber)
    }

    func test_canRenumber_atTheDomainBounds() {
        XCTAssertTrue(sheet(cueCount: 1, start: CueNumberValidator.minimum).canRenumber)
        XCTAssertTrue(sheet(cueCount: 1, start: CueNumberValidator.maximum).canRenumber)
    }

    // A single cue never advances, so the interval cannot push it out of range.
    func test_canRenumber_forOneCue_ignoresTheInterval() {
        XCTAssertTrue(sheet(cueCount: 1, start: 1, interval: 100_000).canRenumber)
    }
}
