import AVFoundation
import XCTest
@testable import OnlyCue

final class LTCFullFileAnalysisTests: XCTestCase {

    private let sampleRate = 48_000.0

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

    /// Two channels: 0 is a tone, 1 is silence-then-LTC-then-silence. The
    /// full-file pass must find the middle run and bound it on both sides.
    func test_analyzeFullFile_measuresTheExtentOfATrailingSilentTail() async throws {
        let start = tc(8, 0, 0, 0, .fps30)
        let ltc = LTCFrameStream(startTimecode: start, sampleRate: sampleRate)
            .samples(frameCount: 60)                       // 2 s of LTC
        let silence = [Float](repeating: 0, count: Int(sampleRate))  // 1 s
        let ltcChannel = silence + ltc + silence
        let tone = (0..<ltcChannel.count).map { index in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
        }

        let url = try writeWav(channels: [tone, ltcChannel], sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await LTCAudioReader.analyzeFullFile(from: url, channel: 1)

        let unwrapped = try XCTUnwrap(result)
        XCTAssertEqual(unwrapped.channel, 1)
        XCTAssertGreaterThanOrEqual(unwrapped.frames.count, 55)
        let first = try XCTUnwrap(unwrapped.frames.first)
        let last = try XCTUnwrap(unwrapped.frames.last)
        XCTAssertEqual(Double(first.startSample) / sampleRate, 1.0, accuracy: 0.05)
        XCTAssertEqual(Double(last.startSample) / sampleRate, 3.0, accuracy: 0.1)
    }

    func test_analyzeFullFile_onAChannelWithoutLTC_returnsNil() async throws {
        let ltc = LTCFrameStream(startTimecode: tc(8, 0, 0, 0, .fps30), sampleRate: sampleRate)
            .samples(frameCount: 60)
        let tone = (0..<ltc.count).map { index in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
        }
        let url = try writeWav(channels: [tone, ltc], sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await LTCAudioReader.analyzeFullFile(from: url, channel: 0)
        XCTAssertNil(result)
    }

    func test_analyzeFullFile_outOfRangeChannel_returnsNil() async throws {
        let ltc = LTCFrameStream(startTimecode: tc(8, 0, 0, 0, .fps30), sampleRate: sampleRate)
            .samples(frameCount: 30)
        let url = try writeWav(ltc, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await LTCAudioReader.analyzeFullFile(from: url, channel: 7)
        XCTAssertNil(result)
    }
}
