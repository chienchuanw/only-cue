import XCTest
@testable import OnlyCue

/// #786 — a single click on a cue's text column starts editing, while the
/// leading cue-type colour stripe becomes the row's select/seek handle. The
/// columns cover the row's full width, so without that split there would be no
/// mouse path left to selection or seek at all.
///
/// `CueRowTap` is the pure decision; reading `NSEvent.modifierFlags` and the
/// SwiftUI wiring stay UI-level. Mirrors the `InlineEditGate` split (#573).
final class CueRowTapIntentTests: XCTestCase {

    // MARK: - Text columns (# / Name / Info)

    func test_plainFieldTap_beginsEditing() {
        XCTAssertEqual(
            CueRowTap.intent(target: .field, isExtending: false, isReadOnly: false),
            .beginEdit
        )
    }

    func test_modifiedFieldTap_extendsSelectionInsteadOfEditing() {
        XCTAssertEqual(
            CueRowTap.intent(target: .field, isExtending: true, isReadOnly: false),
            .extendSelection
        )
    }

    /// Show mode locks the columns with `.disabled`, and a disabled SwiftUI
    /// view receives no taps at all — so the modifier state cannot change the
    /// outcome. The table matches reality rather than describing a branch that
    /// can never run.
    func test_readOnlyFieldTap_isIgnoredWhateverTheModifiers() {
        XCTAssertEqual(
            CueRowTap.intent(target: .field, isExtending: false, isReadOnly: true),
            .ignored
        )
        XCTAssertEqual(
            CueRowTap.intent(target: .field, isExtending: true, isReadOnly: true),
            .ignored
        )
    }

    // MARK: - Colour stripe

    func test_plainStripeTap_selectsAndSeeks() {
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, isExtending: false, isReadOnly: false),
            .selectAndSeek
        )
    }

    func test_modifiedStripeTap_extendsSelectionWithoutSeeking() {
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, isExtending: true, isReadOnly: false),
            .extendSelection
        )
    }

    /// The stripe stays live in Show mode: once the columns are locked it is
    /// the only way to jump the playhead from the cue list.
    func test_stripeTap_staysLiveInShowMode() {
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, isExtending: false, isReadOnly: true),
            .selectAndSeek
        )
        XCTAssertEqual(
            CueRowTap.intent(target: .stripe, isExtending: true, isReadOnly: true),
            .extendSelection
        )
    }
}
