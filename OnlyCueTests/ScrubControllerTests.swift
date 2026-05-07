import XCTest
@testable import OnlyCue

final class ScrubControllerTests: XCTestCase {

    func test_begin_whilePlaying_marksResumeOnRelease() throws {
        var controller = ScrubController()
        controller.begin(originalTime: 5, isPlaying: true)
        let state = try XCTUnwrap(controller.state)
        XCTAssertTrue(state.resumeOnRelease)
        XCTAssertEqual(state.scrubTime, 5, accuracy: 0.001)
    }

    func test_begin_whilePaused_doesNotResumeOnRelease() throws {
        var controller = ScrubController()
        controller.begin(originalTime: 5, isPlaying: false)
        let state = try XCTUnwrap(controller.state)
        XCTAssertFalse(state.resumeOnRelease)
    }

    func test_update_setsScrubTimeFromGeometry() throws {
        var controller = ScrubController()
        controller.begin(originalTime: 12, isPlaying: false)
        controller.update(dx: 50, width: 200, duration: 30)
        XCTAssertEqual(try XCTUnwrap(controller.state).scrubTime, 19.5, accuracy: 0.001)
    }

    func test_update_clampsAtZero() throws {
        var controller = ScrubController()
        controller.begin(originalTime: 1, isPlaying: false)
        controller.update(dx: -200, width: 200, duration: 30)
        XCTAssertEqual(try XCTUnwrap(controller.state).scrubTime, 0, accuracy: 0.001)
    }

    func test_update_clampsAtDuration() throws {
        var controller = ScrubController()
        controller.begin(originalTime: 28, isPlaying: false)
        controller.update(dx: 200, width: 200, duration: 30)
        XCTAssertEqual(try XCTUnwrap(controller.state).scrubTime, 30, accuracy: 0.001)
    }

    func test_end_returnsFinalTimeAndClearsState() throws {
        var controller = ScrubController()
        controller.begin(originalTime: 10, isPlaying: true)
        controller.update(dx: 20, width: 200, duration: 30)
        let finished = try XCTUnwrap(controller.end())
        XCTAssertEqual(finished.scrubTime, 13, accuracy: 0.001)
        XCTAssertTrue(finished.resumeOnRelease)
        XCTAssertNil(controller.state)
    }

    func test_end_withoutBegin_returnsNil() {
        var controller = ScrubController()
        XCTAssertNil(controller.end())
    }
}
