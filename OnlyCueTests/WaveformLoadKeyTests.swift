import XCTest
@testable import OnlyCue

/// #715 — the waveform load task must re-fire when the detected LTC channel
/// changes (async detection arrives after the clip loads). `WaveformLoadKey`
/// captures both the asset URL and the excluding-channel so `.task(id:)` sees
/// the change and restarts.
final class WaveformLoadKeyTests: XCTestCase {

    private let url = URL(string: "file:///track.wav")!

    func test_equalWhenBothNilChannel() {
        XCTAssertEqual(
            WaveformLoadKey(url: url, excludingChannel: nil),
            WaveformLoadKey(url: url, excludingChannel: nil)
        )
    }

    func test_equalWhenSameChannel() {
        XCTAssertEqual(
            WaveformLoadKey(url: url, excludingChannel: 1),
            WaveformLoadKey(url: url, excludingChannel: 1)
        )
    }

    func test_differsWhenChannelChangesFromNilToDetected() {
        XCTAssertNotEqual(
            WaveformLoadKey(url: url, excludingChannel: nil),
            WaveformLoadKey(url: url, excludingChannel: 0),
            "Detection arriving must trigger task regeneration"
        )
    }

    func test_differsWhenChannelIndexChanges() {
        XCTAssertNotEqual(
            WaveformLoadKey(url: url, excludingChannel: 0),
            WaveformLoadKey(url: url, excludingChannel: 1)
        )
    }

    func test_differsWhenURLChanges() {
        let other = URL(string: "file:///other.wav")!
        XCTAssertNotEqual(
            WaveformLoadKey(url: url, excludingChannel: nil),
            WaveformLoadKey(url: other, excludingChannel: nil)
        )
    }
}
