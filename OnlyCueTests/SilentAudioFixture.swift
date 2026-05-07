import AVFoundation
import XCTest

enum SilentAudioFixture {

    static func makeWAV(duration: TimeInterval, file: StaticString = #file, line: UInt = #line) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
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
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
        return url
    }
}
