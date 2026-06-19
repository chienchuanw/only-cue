import XCTest
@testable import OnlyCue

/// #573 — while an inline cue field (name/number/fade) is being edited, the
/// bare arrow-key transport/step shortcuts must yield to the text field so the
/// caret can move. `InlineEditGate` is the pure predicate the shortcut hosts
/// consult; the FocusedValue wiring that feeds it is UI-level.
final class InlineEditGateTests: XCTestCase {

    func test_isEditing_treatsNilAndFalseAsNotEditing() {
        XCTAssertFalse(InlineEditGate.isEditing(nil))
        XCTAssertFalse(InlineEditGate.isEditing(false))
    }

    func test_isEditing_trueWhenFieldFocused() {
        XCTAssertTrue(InlineEditGate.isEditing(true))
    }

    func test_stepShortcutsEnabled_onlyWithActiveItemAndNotEditing() {
        XCTAssertTrue(InlineEditGate.stepShortcutsEnabled(hasActiveItem: true, isEditingCueField: false))
    }

    func test_stepShortcutsDisabled_whileEditing() {
        XCTAssertFalse(InlineEditGate.stepShortcutsEnabled(hasActiveItem: true, isEditingCueField: true))
    }

    func test_stepShortcutsDisabled_withoutActiveItem() {
        XCTAssertFalse(InlineEditGate.stepShortcutsEnabled(hasActiveItem: false, isEditingCueField: false))
        XCTAssertFalse(InlineEditGate.stepShortcutsEnabled(hasActiveItem: false, isEditingCueField: true))
    }
}
