import XCTest
import SwiftUI
@testable import OnlyCue

/// Compile-time guards that `CueRowView` exposes the new stripe + fade
/// surface area. Pixel-level rendering is exercised by the UI tests in
/// `OnlyCueUITests/CueInspectorMinimalUITests.swift`.
@MainActor
final class CueRowViewStripeTests: XCTestCase {

    private func makeCue(fade: FadeTime = .zero) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: nil,
            name: "Test",
            time: 0,
            notes: "",
            fadeTime: fade
        )
    }

    func test_rowAcceptsResolvedColorHex() {
        let view = CueRowView(cue: makeCue(), resolvedColorHex: "#FF8800")
        XCTAssertNotNil(Mirror(reflecting: view))
    }

    func test_rowAcceptsFadeColumnWidth() {
        let view = CueRowView(cue: makeCue(), fadeColumnWidth: 80)
        XCTAssertNotNil(Mirror(reflecting: view))
    }

    func test_rowAcceptsOnCommitFadeCallback() {
        var captured: FadeTime?
        let view = CueRowView(
            cue: makeCue(),
            fadeColumnWidth: 80,
            onCommitFade: { captured = $0 }
        )
        _ = view
        XCTAssertNil(captured)
    }
}
