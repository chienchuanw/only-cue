import AVFoundation
import XCTest
@testable import OnlyCue

final class LTCAudioReaderTests: XCTestCase {

    private func tc(
        _ hours: Int, _ minutes: Int, _ seconds: Int, _ frames: Int, _ rate: SMPTEFramerate = .fps30
    ) -> Timecode {
        guard let timecode = Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate) else {
            preconditionFailure("invalid test timecode")
        }
        return timecode
    }

    /// Write `samples` as a mono 32-bit-float WAV at `sampleRate`; returns the
    /// temp URL (caller deletes it).
    private func writeWav(_ samples: [Float], sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        try samples.withUnsafeBufferPointer { source in
            let base = try XCTUnwrap(source.baseAddress)
            channel.pointee.update(from: base, count: samples.count)
        }
        try file.write(from: buffer)
        return url
    }

    /// Write per-channel `channels` as an interleaved 32-bit-float WAV. All
    /// channels must be the same length.
    private func writeWav(channels: [[Float]], sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let frames = try XCTUnwrap(channels.first?.count)
        let format = try makeFormat(channels: channels.count, sampleRate: sampleRate)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(buffer.floatChannelData)
        for (index, samples) in channels.enumerated() {
            try samples.withUnsafeBufferPointer { source in
                data[index].update(from: try XCTUnwrap(source.baseAddress), count: frames)
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// Above stereo `AVAudioFormat(commonFormat:sampleRate:channels:interleaved:)`
    /// returns nil — a channel count with no layout is not a describable format.
    /// Discrete-in-order matches how a delivery mix's separate feeds are read.
    private func makeFormat(channels: Int, sampleRate: Double) throws -> AVAudioFormat {
        guard channels > 2 else {
            return try XCTUnwrap(
                AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: sampleRate,
                    channels: AVAudioChannelCount(channels),
                    interleaved: false
                )
            )
        }
        let layout = try XCTUnwrap(
            AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels))
        )
        return try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                interleaved: false,
                channelLayout: layout
            )
        )
    }

    /// Loud programme audio, the thing that swamps LTC when channels are summed.
    private func tone(count: Int, sampleRate: Double) -> [Float] {
        (0..<count).map { Float(sin(2 * .pi * 440 * Double($0) / sampleRate)) }
    }

    // The common delivery shape: programme audio on L, timecode on R. Summing to
    // mono buries the biphase square wave under the music, so the decoder — which
    // works from zero crossings — must see the channel on its own.
    func test_decodeTimecodes_ltcOnOneChannelOfAStereoMix_decodes() async throws {
        let start = tc(2, 0, 0, 0, .fps25)
        let ltc = LTCFrameStream(startTimecode: start, sampleRate: 48_000).samples(frameCount: 10)
        let url = try writeWav(
            channels: [tone(count: ltc.count, sampleRate: 48_000), ltc],
            sampleRate: 48_000
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try await LTCAudioReader.detectTimecodes(from: url)
        let first = try XCTUnwrap(decoded.first?.timecode)
        XCTAssertEqual(first.rate, .fps25)
        // The leading partial frame may be clipped, same one-frame slack the
        // mono round-trip test allows.
        XCTAssertLessThanOrEqual(first.frameCount - start.frameCount, 1)
        XCTAssertGreaterThanOrEqual(first.frameCount, start.frameCount)
        XCTAssertGreaterThanOrEqual(decoded.count, 8)
    }

    // The headline case, and the one the `AVChannelLayoutKey` code exists for:
    // a 6-channel delivery mix with timecode on the last channel. Above stereo
    // `AVAssetReader` refuses the read outright without an explicit layout, so
    // without this test that branch never executes in CI.
    //
    // The fixture is discrete-in-order, not positional 5.1 — a positionally
    // tagged source can invoke a mixing matrix instead of a pass-through, which
    // only the spec's hardware-verification step covers. Don't read this green
    // test as proof that a real 5.1/7.1 delivery passes through un-mixed.
    func test_detectTimecodes_ltcOnTheLastChannelOfASixChannelMix_decodes() async throws {
        let start = tc(3, 0, 0, 0, .fps25)
        let ltc = LTCFrameStream(startTimecode: start, sampleRate: 48_000).samples(frameCount: 10)
        let programme = tone(count: ltc.count, sampleRate: 48_000)
        let url = try writeWav(
            channels: Array(repeating: programme, count: 5) + [ltc],
            sampleRate: 48_000
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try await LTCAudioReader.detectTimecodes(from: url)
        let first = try XCTUnwrap(decoded.first?.timecode)
        XCTAssertEqual(first.rate, .fps25)
        XCTAssertLessThanOrEqual(first.frameCount - start.frameCount, 1)
        XCTAssertGreaterThanOrEqual(first.frameCount, start.frameCount)

        // Non-vacuity: the down-mix of the same file finds nothing.
        let downmixed = try await LTCAudioReader.decodeTimecodes(from: url)
        XCTAssertTrue(downmixed.isEmpty, "the down-mix must not decode — otherwise this proves nothing")
    }

    // A cancelled scan must not quietly return a partial answer that then gets
    // cached and labelled `FILE` (#712).
    func test_detectTimecodes_cancelledTask_throws() async throws {
        let ltc = LTCFrameStream(startTimecode: tc(5, 0, 0, 0, .fps25), sampleRate: 48_000).samples(frameCount: 10)
        let url = try writeWav(ltc, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let task = Task { try await LTCAudioReader.detectTimecodes(from: url) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled scan should throw, not return frames")
        } catch is CancellationError {
            // expected
        }
    }

    // One lucky sync-word + parity + BCD match in minutes of programme audio
    // would otherwise re-base the entire readout on a garbage frame.
    func test_isCorroborated_requiresTwoConsecutiveFrames() throws {
        func frame(_ frameCount: Int) -> LTCDecoder.DecodedFrame {
            LTCDecoder.DecodedFrame(timecode: Timecode(frameCount: frameCount, rate: .fps25), startSample: 0)
        }
        XCTAssertFalse(LTCAudioReader.isCorroborated([]))
        XCTAssertFalse(LTCAudioReader.isCorroborated([frame(100)]), "a lone frame is not evidence")
        XCTAssertFalse(LTCAudioReader.isCorroborated([frame(100), frame(4000)]), "unrelated frames are not a run")
        XCTAssertTrue(LTCAudioReader.isCorroborated([frame(100), frame(101)]))
        XCTAssertTrue(LTCAudioReader.isCorroborated([frame(100), frame(4000), frame(4001)]))
        // The decoder drops a frame it can't parse but still advances past it,
        // so real-but-noisy LTC reads as 100, 102 — rejecting that would mean
        // showing nothing for a file that plainly carries timecode.
        XCTAssertTrue(LTCAudioReader.isCorroborated([frame(100), frame(102)]))
        XCTAssertFalse(LTCAudioReader.isCorroborated([frame(100), frame(104)]), "a 4-frame jump is not a run")
    }

    // An ordinary music file must not be relabelled `FILE` by one chance
    // sync-word + parity + BCD match, so an uncorroborated frame is discarded
    // rather than returned as a last resort (#712).
    func test_detectTimecodes_returnsNothingWhenNoChannelCorroborates() async throws {
        let url = try writeWav(tone(count: 48_000, sampleRate: 48_000), sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try await LTCAudioReader.detectTimecodes(from: url)
        XCTAssertTrue(decoded.isEmpty)
    }

    func test_channel_slicesInterleavedSamplesAndPassesMonoThrough() {
        let interleaved: [Float] = [1, 10, 100, 2, 20, 200, 3, 30, 300]
        XCTAssertEqual(AudioSampleReader.channel(0, of: 3, in: interleaved), [1, 2, 3])
        XCTAssertEqual(AudioSampleReader.channel(2, of: 3, in: interleaved), [100, 200, 300])
        XCTAssertEqual(AudioSampleReader.channel(0, of: 1, in: [1, 2, 3]), [1, 2, 3])
    }

    // Non-vacuity guard for the test above: the mono down-mix of that same file
    // decodes nothing, so the per-channel pass is doing the work.
    func test_decodeTimecodes_monoDownmixOfThatSameMix_findsNothing() async throws {
        let start = tc(2, 0, 0, 0, .fps25)
        let ltc = LTCFrameStream(startTimecode: start, sampleRate: 48_000).samples(frameCount: 10)
        let url = try writeWav(
            channels: [tone(count: ltc.count, sampleRate: 48_000), ltc],
            sampleRate: 48_000
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let downmixed = try await LTCAudioReader.decodeTimecodes(from: url)
        XCTAssertTrue(downmixed.isEmpty)
    }

    // A pre-roll, a countdown or leading silence pushes the first LTC frame past
    // the cheap 10 s window; the scan must widen rather than report "no LTC".
    func test_detectTimecodes_ltcStartingAfterTheFirstWindow_isFoundByTheWiderScan() async throws {
        let start = tc(4, 0, 0, 0, .fps25)
        let silence = [Float](repeating: 0, count: 12 * 48_000)
        let ltc = LTCFrameStream(startTimecode: start, sampleRate: 48_000).samples(frameCount: 25)
        let url = try writeWav(silence + ltc, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let narrow = try await LTCAudioReader.detectTimecodes(from: url, windows: [10])
        XCTAssertTrue(
            narrow.isEmpty,
            "the 10 s window alone must not find it — otherwise this test proves nothing"
        )
        let decoded = try await LTCAudioReader.detectTimecodes(from: url)
        XCTAssertEqual(try XCTUnwrap(decoded.first?.timecode).rate, .fps25)
        XCTAssertGreaterThanOrEqual(decoded.count, 20)
    }

    func test_readMonoSamples_roundTripsThroughWrittenFile() async throws {
        let pcm = LTCFrameStream(startTimecode: tc(1, 2, 3, 4), sampleRate: 48_000).samples(frameCount: 8)
        let url = try writeWav(pcm, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try await LTCAudioReader.readMonoSamples(from: url)
        // The reader passes 48 kHz float through; allow a few samples of edge slack.
        XCTAssertEqual(Double(read.count), Double(pcm.count), accuracy: 64)
        XCTAssertTrue(read.contains { $0 != 0 }, "should not be silence")
    }

    func test_decodeTimecodes_recoversTheStripedRun() async throws {
        let start = tc(10, 20, 30, 5, .fps25)
        let count = 10
        let pcm = LTCFrameStream(startTimecode: start, sampleRate: 48_000).samples(frameCount: count)
        let url = try writeWav(pcm, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try await LTCAudioReader.decodeTimecodes(from: url)
        XCTAssertGreaterThanOrEqual(decoded.count, count - 2)
        let recovered = decoded.map(\.timecode)
        let expectedFull = (0..<count).map { Timecode(frameCount: start.frameCount + $0, rate: start.rate) }
        let firstRecovered = try XCTUnwrap(recovered.first)
        let offset = try XCTUnwrap(expectedFull.firstIndex(of: firstRecovered))
        XCTAssertLessThanOrEqual(offset, 1)
        XCTAssertEqual(recovered, Array(expectedFull[offset..<(offset + recovered.count)]))
        XCTAssertEqual(decoded.first?.timecode.rate, .fps25)
    }

    func test_readMonoSamples_nonMediaFile_throws() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("definitely not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await LTCAudioReader.readMonoSamples(from: url)
            XCTFail("reading a non-media file should throw")
        } catch {
            // Either AVFoundation rejects it, or we report `.noAudioTrack` — both fine.
        }
    }

    func test_decodeTimecodes_silentFile_yieldsNothing() async throws {
        let url = try writeWav([Float](repeating: 0, count: 48_000), sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await LTCAudioReader.decodeTimecodes(from: url)
        XCTAssertTrue(decoded.isEmpty)
    }
}
