import XCTest
import SwiftUI
import AppKit
@testable import OnlyCue

/// Pins the section-header row at the top of the cue list pane (audit §7.6 /
/// #408): uppercase `CUES` caption + pluralised `{N} cues` count badge.
final class CueListSectionHeaderTests: XCTestCase {

    func test_countText_zero_isPluralised() {
        XCTAssertEqual(CueListSectionHeader.countText(for: 0), "0 cues")
    }

    func test_countText_one_isSingular() {
        XCTAssertEqual(CueListSectionHeader.countText(for: 1), "1 cue")
    }

    func test_countText_many_isPluralised() {
        XCTAssertEqual(CueListSectionHeader.countText(for: 6), "6 cues")
    }

    func test_headerRendersCaptionAndCount() {
        let host = NSHostingView(rootView: CueListSectionHeader(count: 6))
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(
            host.fittingSize.width,
            0,
            "Section header should lay out non-empty intrinsic content."
        )
    }
}
