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

    func test_importMedia_singleFile_appendsItemAndLoadsAsset() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = CueListDocument()
        let engine = PlayerEngine()

        try await MediaImporter.importMedia(from: [url], into: document, engine: engine)

        XCTAssertEqual(document.model.items.count, 1)
        let item = try XCTUnwrap(document.model.activeItem)
        XCTAssertEqual(item.media.kind, .audio)
        XCTAssertEqual(item.media.displayName, url.lastPathComponent)
        XCTAssertEqual(item.media.duration, 2.0, accuracy: 0.1)
        XCTAssertFalse(item.media.bookmarkData.isEmpty)
        XCTAssertEqual(engine.duration, 2.0, accuracy: 0.1)
    }

    func test_importMedia_multipleFiles_appendsAllInOrder() async throws {
        let url1 = try SilentAudioFixture.makeWAV(duration: 1)
        let url2 = try SilentAudioFixture.makeWAV(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let document = CueListDocument()
        let engine = PlayerEngine()

        try await MediaImporter.importMedia(from: [url1, url2], into: document, engine: engine)

        XCTAssertEqual(document.model.items.count, 2)
        XCTAssertEqual(document.model.items[0].media.displayName, url1.lastPathComponent)
        XCTAssertEqual(document.model.items[1].media.displayName, url2.lastPathComponent)
        XCTAssertEqual(document.model.activeItemID, document.model.items.first?.id,
                       "first newly-imported item becomes active when document was empty")
    }

    func test_importMedia_partialFailure_importsValid_andReportsBatchError() async throws {
        let validURL = try SilentAudioFixture.makeWAV(duration: 1)
        let unsupportedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        try Data("not media".utf8).write(to: unsupportedURL)
        defer {
            try? FileManager.default.removeItem(at: validURL)
            try? FileManager.default.removeItem(at: unsupportedURL)
        }

        let document = CueListDocument()
        let engine = PlayerEngine()

        do {
            try await MediaImporter.importMedia(from: [validURL, unsupportedURL], into: document, engine: engine)
            XCTFail("expected batch error for partial failure")
        } catch let MediaImportError.batch(unsupported) {
            XCTAssertEqual(unsupported, [unsupportedURL.lastPathComponent])
        }

        XCTAssertEqual(document.model.items.count, 1, "valid file was still imported")
    }

    func test_importMedia_intoNonEmptyDoc_preservesPriorActive() async throws {
        let url1 = try SilentAudioFixture.makeWAV(duration: 1)
        let url2 = try SilentAudioFixture.makeWAV(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let document = CueListDocument()
        let engine = PlayerEngine()
        try await MediaImporter.importMedia(from: [url1], into: document, engine: engine)
        let firstID = try XCTUnwrap(document.model.activeItemID)

        try await MediaImporter.importMedia(from: [url2], into: document, engine: engine)

        XCTAssertEqual(document.model.items.count, 2)
        XCTAssertEqual(document.model.activeItemID, firstID, "second import does not steal focus")
    }

    func test_loadActive_resolvesBookmarkAndLoadsAsset() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = CueListDocument()
        let engine = PlayerEngine()
        try await MediaImporter.importMedia(from: [url], into: document, engine: engine)

        let freshEngine = PlayerEngine()
        try await MediaImporter.loadActive(into: document, engine: freshEngine)

        XCTAssertEqual(freshEngine.duration, 1.0, accuracy: 0.1)
    }

    func test_loadActive_missingFile_throwsAndPreservesItem() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        let document = CueListDocument()
        let engine = PlayerEngine()
        try await MediaImporter.importMedia(from: [url], into: document, engine: engine)

        try FileManager.default.removeItem(at: url)

        do {
            try await MediaImporter.loadActive(into: document, engine: engine)
            XCTFail("expected loadActive to throw on missing file")
        } catch {
            // expected
        }
        XCTAssertEqual(document.model.items.count, 1, "media reference is preserved so user can relink")
    }

    func test_loadActive_noActive_unloadsEngine() async throws {
        let document = CueListDocument()
        let engine = PlayerEngine()
        try await MediaImporter.loadActive(into: document, engine: engine)

        XCTAssertEqual(engine.duration, 0)
        XCTAssertEqual(engine.currentTime, 0)
    }

    func test_importMedia_unsupportedSingleFile_throwsBatchError() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("not a media file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = CueListDocument()
        let engine = PlayerEngine()

        do {
            try await MediaImporter.importMedia(from: [url], into: document, engine: engine)
            XCTFail("expected batch error")
        } catch let MediaImportError.batch(unsupported) {
            XCTAssertEqual(unsupported, [url.lastPathComponent])
        }
        XCTAssertTrue(document.model.items.isEmpty)
    }
}
