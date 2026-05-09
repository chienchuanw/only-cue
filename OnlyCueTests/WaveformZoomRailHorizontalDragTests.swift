import XCTest
@testable import OnlyCue

@MainActor
final class WaveformZoomRailHorizontalDragTests: XCTestCase {

    func test_applyDrag_zeroTranslation_keepsBaseline() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        controller.applyDrag(
            translation: 0,
            baseline: 2,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(controller.zoom, 2, accuracy: 0.0001)
    }

    func test_applyDrag_dragRightOneStepDistance_zoomsInOneStep() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        let baseline: CGFloat = 2
        controller.applyDrag(
            translation: WaveformZoomController.dragPixelsPerStep,
            baseline: baseline,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(
            controller.zoom,
            baseline * WaveformZoomController.zoomStep,
            accuracy: 0.0001,
            "drag right by one dragPixelsPerStep must multiply baseline by zoomStep"
        )
    }

    func test_applyDrag_dragLeftOneStepDistance_zoomsOutOneStep() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        let baseline: CGFloat = 4
        controller.applyDrag(
            translation: -WaveformZoomController.dragPixelsPerStep,
            baseline: baseline,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(
            controller.zoom,
            baseline / WaveformZoomController.zoomStep,
            accuracy: 0.0001
        )
    }

    func test_applyDrag_clampsAtMaxOnExtremeRightDrag() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        controller.applyDrag(
            translation: 10000,
            baseline: 1,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(controller.zoom, WaveformZoomController.maxZoom)
    }

    func test_applyDrag_clampsAtMinOnExtremeLeftDrag() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        controller.applyDrag(
            translation: -10000,
            baseline: 4,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(controller.zoom, WaveformZoomController.minZoom)
    }

    func test_applyDrag_anchorsScrollOffsetToCursorFraction() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        controller.applyDrag(
            translation: WaveformZoomController.dragPixelsPerStep,
            baseline: 1,
            anchorFraction: 1.0,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(controller.zoom, WaveformZoomController.zoomStep, accuracy: 0.0001)
        XCTAssertEqual(offset, 200, accuracy: 0.5)
    }
}
