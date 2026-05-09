import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class WaveformZoomMagnifierTests: XCTestCase {

    /// Build a container in a state ready for drag dispatch. Sets `viewportWidth`
    /// to a stable test value (400pt) so horizontal scroll-anchor math is
    /// deterministic.
    ///
    /// Note: `WaveformContainer` is a struct, but the test mutates state via
    /// `container.zoom` and `container.verticalZoom` — both reference-typed
    /// `@Observable` controllers. Mutations through those references survive
    /// struct copies, which is what makes these tests work outside the SwiftUI
    /// runtime. Don't refactor by extracting `let zoom = container.zoom` and
    /// expecting it to be a value; the controller IS the shared mutable state.
    private func makeContainer() -> WaveformContainer {
        let url = URL(fileURLWithPath: "/dev/null")
        let container = WaveformContainer(asset: AVURLAsset(url: url))
        container.viewportWidth = 400
        return container
    }

    func test_applyMagnifierDrag_pureHorizontal_zoomsHorizontalOnly_andAnchorsAtCenter() {
        let container = makeContainer()

        // dragPixelsPerStep = 60; one full step = 1.5× zoom.
        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 60,
            translationY: 0,
            hBaseline: 1.0,
            vBaseline: 1.0
        ))

        XCTAssertEqual(container.zoom.zoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(container.verticalZoom.zoom, 1.0, accuracy: 0.001, "vertical untouched")
        XCTAssertEqual(
            container.scrollOffset,
            100,
            accuracy: 0.5,
            "center-anchored: viewport 400, zoomed to 1.5× → content 600, anchor 0.5 → offset 100"
        )
    }

    func test_applyMagnifierDrag_pureVertical_zoomsVerticalOnly() {
        let container = makeContainer()

        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 0,
            translationY: -60,
            hBaseline: 1.0,
            vBaseline: 1.0
        ))

        XCTAssertEqual(container.zoom.zoom, 1.0, accuracy: 0.001, "horizontal untouched")
        XCTAssertEqual(
            container.verticalZoom.zoom,
            1.5,
            accuracy: 0.001,
            "vertical drag uses negative-up convention — drag up zooms in"
        )
        XCTAssertEqual(container.scrollOffset, 0, accuracy: 0.5)
    }

    func test_applyMagnifierDrag_diagonal_appliesBoth() {
        let container = makeContainer()

        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 60,
            translationY: -60,
            hBaseline: 1.0,
            vBaseline: 1.0
        ))

        XCTAssertEqual(container.zoom.zoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(container.verticalZoom.zoom, 1.5, accuracy: 0.001)
    }

    func test_applyMagnifierReset_resetsBothAxes() {
        let container = makeContainer()

        // Pre-zoom both axes via the drag helper (avoids touching internals).
        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 120,    // 2 steps → 2.25×
            translationY: -120,   // 2 steps → 2.25×
            hBaseline: 1.0,
            vBaseline: 1.0
        ))
        XCTAssertGreaterThan(container.zoom.zoom, 1.0)
        XCTAssertGreaterThan(container.verticalZoom.zoom, 1.0)

        container.applyMagnifierReset()

        XCTAssertEqual(container.zoom.zoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(container.verticalZoom.zoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(container.scrollOffset, 0, accuracy: 0.5)
    }
}
