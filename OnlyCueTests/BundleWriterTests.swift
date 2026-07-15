import XCTest
@testable import OnlyCue

/// #640 — `BundleWriter` performs the bundle's file I/O: create `media/`, copy
/// each planned source file in, and write the `.cuelist` with `bundlePath`
/// stamped onto every item. Integration-tested against a temp directory (no
/// NSSavePanel / no GUI).
final class BundleWriterTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundlewriter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeSourceFile(_ name: String, bytes: [UInt8]) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func makeItem(id: UUID, name: String) -> MediaItem {
        MediaItem(
            id: id,
            media: MediaReference(displayName: name, kind: .audio, duration: 1, bookmarkData: Data([9])),
            cues: []
        )
    }

    func test_write_copiesMediaAndStampsBundlePathsInCuelist() throws {
        let fileA = try makeSourceFile("a.wav", bytes: [1, 2, 3])
        let fileB = try makeSourceFile("b.wav", bytes: [4, 5])
        let idA = UUID()
        let idB = UUID()
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "Show",
            cuePointTypes: [],
            items: [makeItem(id: idA, name: "a.wav"), makeItem(id: idB, name: "b.wav")],
            activeItemID: idA
        )
        let layout = BundleLayout.plan([
            .init(id: idA, name: "a.wav", url: fileA),
            .init(id: idB, name: "b.wav", url: fileB)
        ])
        let destination = tempRoot.appendingPathComponent("Show", isDirectory: true)

        try BundleWriter.write(layout: layout, model: model, to: destination)

        let fileManager = FileManager.default
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("media/a.wav")),
            Data([1, 2, 3])
        )
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("media/b.wav").path))

        let cuelist = destination.appendingPathComponent("Show.cuelist")
        let decoded = try CueListDocument.decodeModel(from: Data(contentsOf: cuelist))
        XCTAssertEqual(decoded.items.first { $0.id == idA }?.media.bundlePath, "media/a.wav")
        XCTAssertEqual(decoded.items.first { $0.id == idB }?.media.bundlePath, "media/b.wav")
    }
}
