import XCTest
@testable import OnlyCue

/// `PotPlayerBundleWriter` copies each located video flat into the destination
/// and writes a paired `<stem>.pbf` (cues filtered to exclude export-disabled
/// Types). The `.pbf` is UTF-16 little-endian with a `FF FE` BOM — the byte
/// format PotPlayer itself authors. Integration-tested against a temp directory.
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

    /// Reads a `.pbf` back through the UTF-16 BOM (strips it, honors LE), giving
    /// the logical text the exporter produced.
    private func readPBF(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf16)
    }

    private func makeSourceFile(_ name: String, bytes: [UInt8]) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func cue(type: UUID, number: Double, name: String, time: TimeInterval) -> Cue {
        Cue(
            id: UUID(),
            typeID: type,
            cueNumber: number,
            name: name,
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    private func item(id: UUID, name: String, cues: [Cue], startTCFrames: Int = 0) -> MediaItem {
        let media = MediaReference(displayName: name, kind: .video, duration: 60, bookmarkData: Data([9]))
        return MediaItem(id: id, media: media, cues: cues, startTimecodeFrames: startTCFrames)
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

    func test_write_pbfIsUTF16LEWithBOM() throws {
        let type = UUID()
        let itemID = UUID()
        let source = try makeSourceFile("intro.mp4", bytes: [1])
        let intro = cue(type: type, number: 1, name: "副歌", time: 5)
        let project = model(
            types: [CuePointType(id: type, name: "L", colorHex: "#fff")],
            items: [item(id: itemID, name: "intro.mp4", cues: [intro])]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "intro.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: project, to: dest)

        let raw = try Data(contentsOf: dest.appendingPathComponent("intro.pbf"))
        XCTAssertEqual(Array(raw.prefix(2)), [0xFF, 0xFE], "must start with UTF-16LE BOM")
        // No lone bytes: UTF-16 is 2 bytes per code unit, so length is even.
        XCTAssertEqual(raw.count % 2, 0)
    }

    func test_write_copiesVideoFlatAndWritesPairedPBF() throws {
        let type = UUID()
        let itemID = UUID()
        let source = try makeSourceFile("intro.mp4", bytes: [1, 2, 3])
        let intro = cue(type: type, number: 1, name: "開場", time: 5)
        let project = model(
            types: [CuePointType(id: type, name: "Lighting", colorHex: "#fff")],
            items: [item(id: itemID, name: "intro.mp4", cues: [intro])]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "intro.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: project, to: dest)

        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("intro.mp4")), Data([1, 2, 3]))
        let pbf = try readPBF(dest.appendingPathComponent("intro.pbf"))
        XCTAssertEqual(pbf, "[Bookmark]\r\n0=5000*[Lighting] 1 開場*\r\n1=\r\n\r\n")
    }

    func test_write_excludesDisabledTypes() throws {
        let shown = UUID()
        let hidden = UUID()
        let itemID = UUID()
        let source = try makeSourceFile("song.mp4", bytes: [1])
        let keep = cue(type: shown, number: 1, name: "keep", time: 1)
        let drop = cue(type: hidden, number: 2, name: "drop", time: 2)
        let project = model(
            types: [
                CuePointType(id: shown, name: "Lighting", colorHex: "#fff", isExportEnabled: true),
                CuePointType(id: hidden, name: "Video", colorHex: "#000", isExportEnabled: false)
            ],
            items: [item(id: itemID, name: "song.mp4", cues: [keep, drop])]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "song.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: project, to: dest)

        let pbf = try readPBF(dest.appendingPathComponent("song.pbf"))
        XCTAssertEqual(pbf, "[Bookmark]\r\n0=1000*[Lighting] 1 keep*\r\n1=\r\n\r\n")
    }

    func test_write_keepsCueWithDanglingType() throws {
        // A cue whose typeID has no matching CuePointType is not "disabled" — it
        // survives (bracket dropped by PBFExporter), unlike an explicitly
        // export-disabled Type.
        let danglingType = UUID()
        let itemID = UUID()
        let source = try makeSourceFile("orphan.mp4", bytes: [1])
        let orphan = cue(type: danglingType, number: 7, name: "orphan", time: 1)
        let project = model(types: [], items: [item(id: itemID, name: "orphan.mp4", cues: [orphan])])
        let layout = BundleLayout.plan([.init(id: itemID, name: "orphan.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: project, to: dest)

        let pbf = try readPBF(dest.appendingPathComponent("orphan.pbf"))
        XCTAssertEqual(pbf, "[Bookmark]\r\n0=1000*7 orphan*\r\n1=\r\n\r\n")
    }

    func test_write_emptyVideoStillGetsPBF() throws {
        let itemID = UUID()
        let source = try makeSourceFile("silent.mp4", bytes: [1])
        let project = model(types: [], items: [item(id: itemID, name: "silent.mp4", cues: [])])
        let layout = BundleLayout.plan([.init(id: itemID, name: "silent.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: project, to: dest)

        let pbf = try readPBF(dest.appendingPathComponent("silent.pbf"))
        XCTAssertEqual(pbf, "[Bookmark]\r\n0=\r\n\r\n")
    }

    func test_write_collisionRenamesVideoAndPBFTogether() throws {
        let type = UUID()
        let idA = UUID()
        let idB = UUID()
        let dirA = tempRoot.appendingPathComponent("a", isDirectory: true)
        let dirB = tempRoot.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let srcA = dirA.appendingPathComponent("intro.mp4")
        let srcB = dirB.appendingPathComponent("intro.mp4")
        try Data([1]).write(to: srcA)
        try Data([2]).write(to: srcB)
        let cueA = cue(type: type, number: 1, name: "a", time: 0)
        let cueB = cue(type: type, number: 2, name: "b", time: 0)
        let project = model(
            types: [CuePointType(id: type, name: "L", colorHex: "#fff")],
            items: [
                item(id: idA, name: "intro.mp4", cues: [cueA]),
                item(id: idB, name: "intro.mp4", cues: [cueB])
            ]
        )
        let layout = BundleLayout.plan([
            .init(id: idA, name: "intro.mp4", url: srcA),
            .init(id: idB, name: "intro.mp4", url: srcB)
        ])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: project, to: dest)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro.mp4").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro.pbf").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro-2.mp4").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro-2.pbf").path))
    }

    func test_write_ignoresStartTimecodeFrames() throws {
        let type = UUID()
        let itemID = UUID()
        let source = try makeSourceFile("offset.mp4", bytes: [1])
        let offsetCue = cue(type: type, number: 1, name: "x", time: 5)
        let offsetItem = item(id: itemID, name: "offset.mp4", cues: [offsetCue], startTCFrames: 90_000)
        let project = model(
            types: [CuePointType(id: type, name: "L", colorHex: "#fff")],
            items: [offsetItem]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "offset.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: project, to: dest)

        let pbf = try readPBF(dest.appendingPathComponent("offset.pbf"))
        XCTAssertEqual(pbf, "[Bookmark]\r\n0=5000*[L] 1 x*\r\n1=\r\n\r\n")
    }
}
