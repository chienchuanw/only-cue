import XCTest
@testable import OnlyCue

final class ScrubControllerTests: XCTestCase {

    func test_begin_whilePlaying_marksResumeOnRelease() {
        var controller = ScrubController()
        controller.begin(originalTime: 5, isPlaying: true)
        XCTAssertEqual(controller.state?.resumeOnRelease, true)
        XCTAssertEqual(controller.state?.scrubTime, 5, accuracy: 0.001)
    }

    func test_begin_whilePaused_doesNotResumeOnRelease() {
        var controller = ScrubController()
        controller.begin(originalTime: 5, isPlaying: false)
        XCTAssertEqual(controller.state?.resumeOnRelease, false)
    }

    func test_update_setsScrubTimeFromGeometry() {
        var controller = ScrubController()
        controller.begin(originalTime: 12, isPlaying: false)
        controller.update(dx: 50, width: 200, duration: 30)
        XCTAssertEqual(controller.state?.scrubTime, 19.5, accuracy: 0.001)
    }

    func test_update_clampsAtZero() {
        var controller = ScrubController()
        controller.begin(originalTime: 1, isPlaying: false)
        controller.update(dx: -200, width: 200, duration: 30)
        XCTAssertEqual(controller.state?.scrubTime, 0, accuracy: 0.001)
    }

    func test_update_clampsAtDuration() {
        var controller = ScrubController()
        controller.begin(originalTime: 28, isPlaying: false)
        controller.update(dx: 200, width: 200, duration: 30)
        XCTAssertEqual(controller.state?.scrubTime, 30, accuracy: 0.001)
    }

    func test_end_returnsFinalTimeAndClearsState() {
        var controller = ScrubController()
        controller.begin(originalTime: 10, isPlaying: true)
        controller.update(dx: 20, width: 200, duration: 30)
        let finished = controller.end()
        XCTAssertEqual(finished?.scrubTime, 13, accuracy: 0.001)
        XCTAssertEqual(finished?.resumeOnRelease, true)
        XCTAssertNil(controller.state)
    }

    func test_end_withoutBegin_returnsNil() {
        var controller = ScrubController()
        XCTAssertNil(controller.end())
    }
}
