import AppKit
import XCTest
@testable import OnlyCue

/// #786 — a single click on a cue's text column starts editing, while the
/// leading cue-type colour stripe becomes the row's select/seek handle. The
/// columns cover the row's full width, so without that split there would be no
/// mouse path left to selection or seek at all.
///
/// #790 splits the modifier the other way: ⌘ toggles one row, ⇧ ranges from the
/// anchor. #786 deliberately collapsed both into one `isExtending` flag to keep
/// this table at eight rows, which cost the list contiguous range selection
/// entirely. The table is twelve rows now; that is the price of the feature.
///
/// `CueRowTap` is the pure decision; reading `NSEvent.modifierFlags` and the
/// SwiftUI wiring stay UI-level. Mirrors the `InlineEditGate` split (#573).
final class CueRowTapIntentTests: XCTestCase {

    // MARK: - Text columns (# / Name / Info)

    func test_plainFieldTap_beginsEditing() {
        XCTAssertEqual(
            CueRowTap.intent(target: .field, modifier: .plain, isReadOnly: false),
            .beginEdit
        )
    }

    func test_commandFieldTap_togglesSelectionInsteadOfEditing() {
        XCTAssertEqual(
            CueRowTap.intent(target: .field, modifier: .toggle, isReadOnly: false),
            .toggleSelection
        )
    }

    /// Acceptance: ⇧-click never opens a `TextField`.
    func test_shiftFieldTap_rangesInsteadOfEditing() {
        XCTAssertEqual(
            CueRowTap.intent(target: .field, modifier: .range, isReadOnly: false),
            .extendRange
        )
    }

    /// Show mode locks the columns with `.disabled`, and a disabled SwiftUI
    /// view receives no taps at all — so the modifier state cannot change the
    /// outcome. The table matches reality rather than describing a branch that
    /// can never run.
    func test_readOnlyFieldTap_isIgnoredWhateverTheModifiers() {
        for modifier in CueRowTapModifier.allCases {
            XCTAssertEqual(
                CueRowTap.intent(target: .field, modifier: modifier, isReadOnly: true),
                .ignored,
                "a locked column takes no taps, \(modifier) or not"
            )
        }
    }

    // MARK: - Colour stripe

    func test_plainStripeTap_selectsAndSeeks() {
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, modifier: .plain, isReadOnly: false),
            .selectAndSeek
        )
    }

    func test_commandStripeTap_togglesSelectionWithoutSeeking() {
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, modifier: .toggle, isReadOnly: false),
            .toggleSelection
        )
    }

    /// Acceptance: ⇧-click never moves the playhead — `.extendRange`, not
    /// `.selectAndSeek`.
    func test_shiftStripeTap_rangesWithoutSeeking() {
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, modifier: .range, isReadOnly: false),
            .extendRange
        )
    }

    /// The stripe stays live in Show mode: once the columns are locked it is
    /// the only way to jump the playhead from the cue list. Acceptance requires
    /// ⇧ to keep ranging there too.
    func test_stripeTap_staysLiveInShowMode() {
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, modifier: .plain, isReadOnly: true),
            .selectAndSeek
        )
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, modifier: .toggle, isReadOnly: true),
            .toggleSelection
        )
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, modifier: .range, isReadOnly: true),
            .extendRange
        )
    }

    // MARK: - Reading the modifier flags

    func test_noModifiers_readAsPlain() {
        XCTAssertEqual(CueRowTapModifier(flags: []), .plain)
    }

    func test_command_readsAsToggle() {
        XCTAssertEqual(CueRowTapModifier(flags: .command), .toggle)
    }

    func test_shift_readsAsRange() {
        XCTAssertEqual(CueRowTapModifier(flags: .shift), .range)
    }

    /// ⌘⇧ means "add the range to what is already selected" in Finder. #790
    /// does not ask for that third mode, so ⇧ simply wins and the click ranges.
    /// Pinned so the precedence is a decision on record, not an accident of
    /// which `if` came first.
    func test_commandAndShiftTogether_rangeWins() {
        XCTAssertEqual(CueRowTapModifier(flags: [.command, .shift]), .range)
    }

    /// Modifiers nobody bound must not silently read as ⌘ or ⇧.
    func test_unrelatedModifiers_readAsPlain() {
        XCTAssertEqual(CueRowTapModifier(flags: [.option, .control]), .plain)
    }
}
