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
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> URL {
        try writeWAV(
            duration: duration,
            fill: { frame, sr in
                sin(2 * .pi * frequency * Double(frame) / sr)
            },
            file: file,
            line: line
        )
    }

    private static func writeWAV(
        duration: TimeInterval,
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
