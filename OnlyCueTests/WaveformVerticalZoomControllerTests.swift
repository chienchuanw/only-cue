import XCTest
@testable import OnlyCue

@MainActor
final class WaveformVerticalZoomControllerTests: XCTestCase {

    func test_setZoom_clampsBelowMin() {
        let controller = WaveformVerticalZoomController()
        controller.setZoom(0.1)
        XCTAssertEqual(controller.zoom, WaveformVerticalZoomController.minZoom)
    }

    func test_setZoom_clampsAboveMax() {
        let controller = WaveformVerticalZoomController()
        controller.setZoom(999)
        XCTAssertEqual(controller.zoom, WaveformVerticalZoomController.maxZoom)
    }

    func test_zoomIn_multipliesByZoomStep() {
        let controller = WaveformVerticalZoomController()
        controller.zoomIn()
        XCTAssertEqual(controller.zoom, WaveformVerticalZoomController.zoomStep)
    }

    func test_zoomOut_dividesByZoomStep_andClampsAtMin() {
        let controller = WaveformVerticalZoomController()
        controller.setZoom(WaveformVerticalZoomController.zoomStep * 2)
        controller.zoomOut()
        XCTAssertEqual(
            controller.zoom,
            (WaveformVerticalZoomController.zoomStep * 2) / WaveformVerticalZoomController.zoomStep,
            accuracy: 0.0001
        )
        controller.zoomOut()
        controller.zoomOut()
        controller.zoomOut()
        XCTAssertEqual(
            controller.zoom,
            WaveformVerticalZoomController.minZoom,
            "zoomOut from 1× must clamp at minZoom (no negative or sub-1× zoom)"
        )
    }

    func test_reset_returnsToOne() {
        let controller = WaveformVerticalZoomController()
        controller.setZoom(4)
        controller.reset()
        XCTAssertEqual(controller.zoom, 1)
    }

    // MARK: - applyDrag

    func test_applyDrag_zeroTranslation_keepsBaseline() {
        let controller = WaveformVerticalZoomController()
        controller.applyDrag(translation: 0, baseline: 2)
        XCTAssertEqual(controller.zoom, 2, accuracy: 0.0001)
    }

    func test_applyDrag_dragUpOneStepDistance_zoomsInOneStep() {
        let controller = WaveformVerticalZoomController()
        let baseline: CGFloat = 2
        controller.applyDrag(
            translation: -WaveformVerticalZoomController.dragPixelsPerStep,
            baseline: baseline
        )
        XCTAssertEqual(
            controller.zoom,
            baseline * WaveformVerticalZoomController.zoomStep,
            accuracy: 0.0001,
            "drag up by one dragPixelsPerStep must multiply baseline by zoomStep"
        )
    }

    func test_applyDrag_dragDownOneStepDistance_zoomsOutOneStep() {
        let controller = WaveformVerticalZoomController()
        let baseline: CGFloat = 4
        controller.applyDrag(
            translation: WaveformVerticalZoomController.dragPixelsPerStep,
            baseline: baseline
        )
        XCTAssertEqual(
            controller.zoom,
            baseline / WaveformVerticalZoomController.zoomStep,
            accuracy: 0.0001,
            "drag down by one dragPixelsPerStep must divide baseline by zoomStep"
        )
    }

    func test_applyDrag_clampsAtMaxOnExtremeUpDrag() {
        let controller = WaveformVerticalZoomController()
        controller.applyDrag(translation: -10000, baseline: 1)
        XCTAssertEqual(controller.zoom, WaveformVerticalZoomController.maxZoom)
    }

    func test_applyDrag_clampsAtMinOnExtremeDownDrag() {
        let controller = WaveformVerticalZoomController()
        controller.applyDrag(translation: 10000, baseline: 4)
        XCTAssertEqual(controller.zoom, WaveformVerticalZoomController.minZoom)
    }
}
