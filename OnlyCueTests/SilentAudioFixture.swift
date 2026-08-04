import AVFoundation
import XCTest

enum SilentAudioFixture {

    static let sampleRate: Double = 44100

    static func makeWAV(duration: TimeInterval, file: StaticString = #file, line: UInt = #line) throws -> URL {
        try writeWAV(duration: duration, fill: nil, file: file, line: line)
    }

    static func makeSineWAV(
        duration: TimeInterval,
        frequency: Double,
        amplitude: Double = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> URL {
        try writeWAV(
            duration: duration,
            fill: { frame, sr in
                amplitude * sin(2 * .pi * frequency * Double(frame) / sr)
            },
            file: file,
            line: line
        )
    }

    /// A file that is silent everywhere except a 2 ms full-scale click whose
    /// onset is at exactly `clickAt` seconds — a deterministic ruler for
    /// audio↔visual alignment measurements (#611).
    static func makeClickWAV(
        duration: TimeInterval,
        clickAt: TimeInterval,
        sampleRate: Double = Self.sampleRate,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> URL {
        let clickStart = Int(clickAt * sampleRate)
        let clickEnd = clickStart + Int(0.002 * sampleRate)
        return try writeWAV(
            duration: duration,
            sampleRate: sampleRate,
            fill: { frame, _ in
                (clickStart..<clickEnd).contains(frame) ? 1.0 : 0.0
            },
            file: file,
            line: line
        )
    }

    /// Arbitrary mono signal from a `fill(frame, sampleRate) -> amplitude`
    /// closure (amplitude in -1…1). Lets a test craft signals like constant-peak
    /// but varying-energy to distinguish RMS from peak rendering (#632).
    static func makeCustomWAV(
        duration: TimeInterval,
        fill: @escaping (Int, Double) -> Double,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> URL {
        try writeWAV(duration: duration, fill: fill, file: file, line: line)
    }

    /// A 2-channel (stereo) WAV file where each channel is filled independently.
    /// `fillCh0(frame, sampleRate)` and `fillCh1(frame, sampleRate)` return
    /// amplitudes in −1…1. Use this when a test needs a file where the two
    /// channels carry audibly different content (e.g. music vs LTC tone).
    static func makeStereoWAV(
        duration: TimeInterval,
        fillCh0: @escaping (Int, Double) -> Double,
        fillCh1: @escaping (Int, Double) -> Double,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.sampleRate,
                channels: 2,
                interleaved: false
            ),
            file: file,
            line: line
        )
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            file: file,
            line: line
        )
        buffer.frameLength = frameCount

        if let ch0 = buffer.floatChannelData?[0], let ch1 = buffer.floatChannelData?[1] {
            for frame in 0..<Int(frameCount) {
                ch0[frame] = Float(fillCh0(frame, format.sampleRate))
                ch1[frame] = Float(fillCh1(frame, format.sampleRate))
            }
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
        return url
    }

    private static func writeWAV(
        duration: TimeInterval,
        sampleRate: Double = Self.sampleRate,
        fill: ((Int, Double) -> Double)?,
        file: StaticString,
        line: UInt
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ),
            file: file,
            line: line
        )
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            file: file,
            line: line
        )
        buffer.frameLength = frameCount

        if let fill, let channel = buffer.floatChannelData?[0] {
            for frame in 0..<Int(frameCount) {
                channel[frame] = Float(fill(frame, format.sampleRate))
            }
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
        return url
    }
}
