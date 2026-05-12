import AVFoundation
import XCTest
@testable import OnlyCue

final class AudioSampleReaderTests: XCTestCase {

    /// Write `samples` as a mono 32-bit-float WAV at `sampleRate`; returns the temp URL.
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
            channel.pointee.update(from: try XCTUnwrap(source.baseAddress), count: samples.count)
        }
        try file.write(from: buffer)
        return url
    }

    private func ramp(seconds: Double, sampleRate: Double = 48_000) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { Float(sin(2.0 * .pi * 440.0 * Double($0) / sampleRate)) }
    }

    func test_readMonoSamples_roundTripsAWrittenFile() async throws {
        let url = try writeWav(ramp(seconds: 2.0), sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try await AudioSampleReader.readMonoSamples(from: url)
        XCTAssertEqual(Double(read.count), 96_000, accuracy: 256)
        XCTAssertTrue(read.contains { abs($0) > 0.5 }, "a 440 Hz tone shouldn't read back as silence")
    }

    func test_readMonoSamples_rangeReadsOnlyThatSpan() async throws {
        let url = try writeWav(ramp(seconds: 4.0), sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try await AudioSampleReader.readMonoSamples(from: url, range: 1.0...2.0)
        // ~1 second of 48 kHz audio, with a little decoder edge slack.
        XCTAssertEqual(Double(read.count), 48_000, accuracy: 2_400)
        XCTAssertLessThan(read.count, 96_000, "the windowed read must be much shorter than the whole file")
    }

    func test_readMonoSamples_nonMediaFile_throws() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await AudioSampleReader.readMonoSamples(from: url)
            XCTFail("expected an error reading a non-media file")
        } catch {
            // A clean AudioSampleReader.Error (or, defensively, any AVFoundation error) — both fine.
        }
    }

    func test_ltcAudioReaderErrorIsTheSameTypeAsAudioSampleReaderError() {
        // The typealias keeps existing LTC callers working after the extraction.
        XCTAssertEqual(LTCAudioReaderError.noAudioTrack, AudioSampleReader.Error.noAudioTrack)
    }
}
