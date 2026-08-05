import XCTest
@testable import OnlyCue

final class MusicOnlyMixerTests: XCTestCase {

    func test_stereo_bothChannelsBecomeMusic_andLTCIsGone() {
        // Channel 0 = music, channel 1 = LTC. With a single surviving music
        // channel the mean is that channel unchanged, and both output channels
        // must carry it — the LTC content must appear in neither.
        let music: [Float] = [0.1, 0.2, -0.3, 0.4]
        let ltc: [Float] = [0.9, -0.9, 0.9, -0.9]

        let out = MusicOnlyMixer.centered(channels: [music, ltc], excludingChannel: 1)

        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0], music)
        XCTAssertEqual(out[1], music)
        // The LTC content is absent from both channels.
        XCTAssertNotEqual(out[0], ltc)
        XCTAssertNotEqual(out[1], ltc)
    }

    func test_threeChannels_ltcInMiddle_everyChannelIsMeanOfTheTwoMusicChannels() {
        // Channels 0 and 2 are music, channel 1 is LTC.
        let musicA: [Float] = [0.2, 0.4, 0.6, 0.8]
        let ltc: [Float] = [0.9, -0.9, 0.9, -0.9]
        let musicB: [Float] = [0.4, 0.8, 1.0, 0.0]
        let expectedMean: [Float] = zip(musicA, musicB).map { ($0 + $1) / 2 }

        let out = MusicOnlyMixer.centered(channels: [musicA, ltc, musicB], excludingChannel: 1)

        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0], expectedMean)
        XCTAssertEqual(out[1], expectedMean) // old LTC position
        XCTAssertEqual(out[2], expectedMean)
    }

    func test_mono_isPassedThroughUnchanged() {
        let mono: [Float] = [0.1, -0.2, 0.3]

        let out = MusicOnlyMixer.centered(channels: [mono], excludingChannel: 0)

        XCTAssertEqual(out, [mono])
    }

    func test_ltcChannelNegative_isPassedThroughUnchanged() {
        let left: [Float] = [0.1, 0.2]
        let right: [Float] = [0.3, 0.4]

        let out = MusicOnlyMixer.centered(channels: [left, right], excludingChannel: -1)

        XCTAssertEqual(out, [left, right])
    }

    func test_ltcChannelOutOfRangeHigh_isPassedThroughUnchanged() {
        let left: [Float] = [0.1, 0.2]
        let right: [Float] = [0.3, 0.4]

        let out = MusicOnlyMixer.centered(channels: [left, right], excludingChannel: 2)

        XCTAssertEqual(out, [left, right])
    }
}
