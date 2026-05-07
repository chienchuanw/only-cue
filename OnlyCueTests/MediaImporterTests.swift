import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class MediaImporterTests: XCTestCase {

    func test_mediaKind_audioExtension_returnsAudio() {
        let url = URL(fileURLWithPath: "/tmp/song.mp3")
        XCTAssertEqual(MediaImporter.mediaKind(for: url), .audio)
    }

    func test_mediaKind_videoExtension_returnsVideo() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        XCTAssertEqual(MediaImporter.mediaKind(for: url), .video)
    }

    func test_mediaKind_unsupportedExtension_returnsNil() {
        let url = URL(fileURLWithPath: "/tmp/doc.pdf")
        XCTAssertNil(MediaImporter.mediaKind(for: url))
    }

    func test_importMedia_populatesModelAndLoadsAsset() async throws {
        let url = try Self.makeSilentWAV(duration: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = CueListDocument()
        let engine = PlayerEngine()

        try await MediaImporter.importMedia(from: url, into: document, engine: engine)

        let media = try XCTUnwrap(document.model.media)
        XCTAssertEqual(media.kind, .audio)
        XCTAssertEqual(media.displayName, url.lastPathComponent)
        XCTAssertEqual(media.duration, 2.0, accuracy: 0.1)
        XCTAssertFalse(media.bookmarkData.isEmpty)
        XCTAssertEqual(engine.duration, 2.0, accuracy: 0.1)
    }

    func test_importMedia_unsupportedType_throwsAndLeavesModelUnchanged() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("not a media file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = CueListDocument()
        let engine = PlayerEngine()

        do {
            try await MediaImporter.importMedia(from: url, into: document, engine: engine)
            XCTFail("expected unsupportedType error")
        } catch let MediaImportError.unsupportedType(rejected) {
            XCTAssertEqual(rejected, url.lastPathComponent)
        }
        XCTAssertNil(document.model.media)
    }

    private static func makeSilentWAV(duration: TimeInterval) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
                channels: 1,
                interleaved: false
            )
        )
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
