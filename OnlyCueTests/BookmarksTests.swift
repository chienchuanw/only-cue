import AVFoundation
import XCTest
@testable import OnlyCue

final class BookmarksTests: XCTestCase {

    func test_roundTrip_resolvesToOriginalURL() throws {
        let url = try Self.makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Bookmarks.create(for: url)
        let resolution = try Bookmarks.resolve(data)

        XCTAssertEqual(resolution.url.standardizedFileURL, url.standardizedFileURL)
        XCTAssertFalse(resolution.isStale)
    }

    func test_jsonRoundTrip_preservesBookmark() throws {
        let url = try Self.makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let original = try Bookmarks.create(for: url)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try XCTUnwrap(JSONDecoder().decode(Data?.self, from: encoded))
        let resolution = try Bookmarks.resolve(decoded)

        XCTAssertEqual(resolution.url.standardizedFileURL, url.standardizedFileURL)
    }

    func test_resolve_invalidData_throws() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try Bookmarks.resolve(garbage))
    }

    private static func makeTempFile() throws -> URL {
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
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate))
        )
        buffer.frameLength = AVAudioFrameCount(format.sampleRate)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
