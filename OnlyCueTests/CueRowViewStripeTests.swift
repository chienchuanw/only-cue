import XCTest
import SwiftUI
@testable import OnlyCue

/// Compile-time guards that `CueRowView` exposes the stripe + Info surface
/// area (#661). Pixel-level rendering is exercised by the UI tests in
/// `OnlyCueUITests/CueInspectorMinimalUITests.swift`.
@MainActor
final class CueRowViewStripeTests: XCTestCase {

    private func makeCue(notes: String = "") -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: nil,
            name: "Test",
            time: 0,
            notes: notes,
            fadeTime: .zero
        )
    }

    func test_rowAcceptsResolvedColorHex() {
        let view = CueRowView(cue: makeCue(), resolvedColorHex: "#FF8800")
        XCTAssertNotNil(Mirror(reflecting: view))
    }

    func test_rowAcceptsInfoColumnWidth() {
        let view = CueRowView(cue: makeCue(), infoColumnWidth: 120)
        XCTAssertNotNil(Mirror(reflecting: view))
    }

    func test_rowAcceptsOnCommitNotesCallback() {
        var captured: String?
        let view = CueRowView(
            cue: makeCue(),
            infoColumnWidth: 120,
            onCommitNotes: { captured = $0 }
        )
        _ = view
        XCTAssertNil(captured)
    }
}
