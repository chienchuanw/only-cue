import AVFoundation
import CoreImage
import XCTest

/// Synthesizes a short solid-color H.264 .mov in the temp directory.
/// Mirrors `SilentAudioFixture` for video poster-frame tests.
enum VideoFixture {

    /// Returns a file URL to a `duration`-second, `size` solid red .mov.
    static func makeMOV(
        duration: TimeInterval,
        size: CGSize = CGSize(width: 160, height: 120),
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let frameCount = max(Int(duration * Double(fps)), 1)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool, file: file, line: line)

        for frame in 0..<frameCount {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer, file: file, line: line)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                // 32ARGB solid red: A=255, R=255, G=0, B=0
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                let count = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
                for i in stride(from: 0, to: count, by: 4) {
                    bytes[i] = 255; bytes[i + 1] = 255; bytes[i + 2] = 0; bytes[i + 3] = 0
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw try XCTUnwrap(writer.error, file: file, line: line)
        }
        return url
    }
}
