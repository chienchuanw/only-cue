import XCTest
@testable import OnlyCue

/// `PotPlayerBundleWriter` copies each located video flat into the destination
/// and writes a paired `<stem>.pbf` (cues filtered to `isExportEnabled` Types).
/// Integration-tested against a temp directory (no NSSavePanel / GUI).
final class PotPlayerBundleWriterTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbfwriter-\(UUID().uuidString)", isDirectory: true)
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

    private func cue(type: UUID, number: Double, name: String, time: TimeInterval) -> Cue {
        Cue(id: UUID(), typeID: type, cueNumber: number, name: name,
            time: time, notes: "", fadeTime: FadeTime(fadeIn: 0, fadeOut: 0))
    }

    private func item(id: UUID, name: String, cues: [Cue], startTCFrames: Int = 0) -> MediaItem {
        MediaItem(
            id: id,
            media: MediaReference(displayName: name, kind: .video, duration: 60, bookmarkData: Data([9])),
            cues: cues,
            startTimecodeFrames: startTCFrames
        )
    }

    private func model(types: [CuePointType], items: [MediaItem]) -> ProjectModel {
        ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "Show",
            cuePointTypes: types,
            items: items,
            activeItemID: items.first?.id
        )
    }

    func test_write_copiesVideoFlatAndWritesPairedPBF() throws {
        let type = UUID()
        let itemID = UUID()
        let source = try makeSourceFile("intro.mp4", bytes: [1, 2, 3])
        let m = model(
            types: [CuePointType(id: type, name: "Lighting", colorHex: "#fff")],
            items: [item(id: itemID, name: "intro.mp4",
                         cues: [cue(type: type, number: 1, name: "開場", time: 5)])]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "intro.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("intro.mp4")), Data([1, 2, 3]))
        let pbf = try String(contentsOf: dest.appendingPathComponent("intro.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n1=5000*[Lighting] 1 開場*\n")
    }

    func test_write_excludesDisabledTypes() throws {
        let shown = UUID(), hidden = UUID(), itemID = UUID()
        let source = try makeSourceFile("song.mp4", bytes: [1])
        let m = model(
            types: [
                CuePointType(id: shown, name: "Lighting", colorHex: "#fff", isExportEnabled: true),
                CuePointType(id: hidden, name: "Video", colorHex: "#000", isExportEnabled: false)
            ],
            items: [item(id: itemID, name: "song.mp4", cues: [
                cue(type: shown, number: 1, name: "keep", time: 1),
                cue(type: hidden, number: 2, name: "drop", time: 2)
            ])]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "song.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let pbf = try String(contentsOf: dest.appendingPathComponent("song.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n1=1000*[Lighting] 1 keep*\n")
    }

    func test_write_emptyVideoStillGetsPBF() throws {
        let itemID = UUID()
        let source = try makeSourceFile("silent.mp4", bytes: [1])
        let m = model(types: [], items: [item(id: itemID, name: "silent.mp4", cues: [])])
        let layout = BundleLayout.plan([.init(id: itemID, name: "silent.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let pbf = try String(contentsOf: dest.appendingPathComponent("silent.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n")
    }

    func test_write_collisionRenamesVideoAndPBFTogether() throws {
        let type = UUID(), idA = UUID(), idB = UUID()
        let dirA = tempRoot.appendingPathComponent("a", isDirectory: true)
        let dirB = tempRoot.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let srcA = dirA.appendingPathComponent("intro.mp4"); try Data([1]).write(to: srcA)
        let srcB = dirB.appendingPathComponent("intro.mp4"); try Data([2]).write(to: srcB)
        let m = model(
            types: [CuePointType(id: type, name: "L", colorHex: "#fff")],
            items: [
                item(id: idA, name: "intro.mp4", cues: [cue(type: type, number: 1, name: "a", time: 0)]),
                item(id: idB, name: "intro.mp4", cues: [cue(type: type, number: 2, name: "b", time: 0)])
            ]
        )
        let layout = BundleLayout.plan([
            .init(id: idA, name: "intro.mp4", url: srcA),
            .init(id: idB, name: "intro.mp4", url: srcB)
        ])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro.mp4").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro.pbf").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro-2.mp4").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro-2.pbf").path))
    }

    func test_write_ignoresStartTimecodeFrames() throws {
        let type = UUID(), itemID = UUID()
        let source = try makeSourceFile("offset.mp4", bytes: [1])
        let m = model(
            types: [CuePointType(id: type, name: "L", colorHex: "#fff")],
            items: [item(id: itemID, name: "offset.mp4",
                         cues: [cue(type: type, number: 1, name: "x", time: 5)],
                         startTCFrames: 90_000)]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "offset.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let pbf = try String(contentsOf: dest.appendingPathComponent("offset.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n1=5000*[L] 1 x*\n")
    }
}
