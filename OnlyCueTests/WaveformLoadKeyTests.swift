import XCTest
@testable import OnlyCue

/// #715 — the waveform load task must re-fire when the detected LTC channel
/// changes (async detection arrives after the clip loads). `WaveformLoadKey`
/// captures the asset URL, the excluding-channel, and (since #720) the
/// Split-Channels flag so `.task(id:)` sees the change and restarts.
final class WaveformLoadKeyTests: XCTestCase {

    private let url = URL(string: "file:///track.wav")!

    func test_equalWhenBothNilChannel() {
        XCTAssertEqual(
            WaveformLoadKey(url: url, excludingChannel: nil, split: false),
            WaveformLoadKey(url: url, excludingChannel: nil, split: false)
        )
    }

    func test_equalWhenSameChannel() {
        XCTAssertEqual(
            WaveformLoadKey(url: url, excludingChannel: 1, split: false),
            WaveformLoadKey(url: url, excludingChannel: 1, split: false)
        )
    }

    func test_equalWhenAllFieldsMatchWithSplitOn() {
        XCTAssertEqual(
            WaveformLoadKey(url: url, excludingChannel: 1, split: true),
            WaveformLoadKey(url: url, excludingChannel: 1, split: true)
        )
    }

    func test_differsWhenChannelChangesFromNilToDetected() {
        XCTAssertNotEqual(
            WaveformLoadKey(url: url, excludingChannel: nil, split: false),
            WaveformLoadKey(url: url, excludingChannel: 0, split: false),
            "Detection arriving must trigger task regeneration"
        )
    }

    func test_differsWhenChannelIndexChanges() {
        XCTAssertNotEqual(
            WaveformLoadKey(url: url, excludingChannel: 0, split: false),
            WaveformLoadKey(url: url, excludingChannel: 1, split: false)
        )
    }

    func test_differsWhenURLChanges() {
        let other = URL(string: "file:///other.wav")!
        XCTAssertNotEqual(
            WaveformLoadKey(url: url, excludingChannel: nil, split: false),
            WaveformLoadKey(url: other, excludingChannel: nil, split: false)
        )
    }

    func test_differsWhenOnlySplitDiffers() {
        XCTAssertNotEqual(
            WaveformLoadKey(url: url, excludingChannel: 1, split: false),
            WaveformLoadKey(url: url, excludingChannel: 1, split: true),
            "Toggling Split Channels must trigger task regeneration"
        )
    }
}
