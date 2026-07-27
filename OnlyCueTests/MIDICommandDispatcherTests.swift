import XCTest
@testable import OnlyCue

final class MIDICommandDispatcherTests: XCTestCase {
    private let snap = MIDIEngineSnapshot(currentTime: 10, duration: 200, rateRange: 0.1...3.0)

    func test_continuousScrub_resolvesToSeekAcrossDuration() {
        let effect = MIDICommandDispatcher.effect(for: .continuous(.scrub), value: 127, engine: snap)
        XCTAssertEqual(effect, .seek(200))
    }

    func test_continuousRate_resolvesToSetRate() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .continuous(.playbackRate), value: 0, engine: snap),
                       .setRate(0.1))
    }

    func test_continuousLTC_resolvesToSetLevel() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .continuous(.ltcLevel), value: 127, engine: snap),
                       .setLTCLevel(1.0))
    }

    func test_discretePlayPause_resolvesToKeymap() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .discrete(.playPause), value: 127, engine: snap),
                       .keymap(.playPause))
    }

    func test_discreteStop_resolvesToKeymapStop() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .discrete(.stop), value: 127, engine: snap),
                       .keymap(.stop))
    }
}
