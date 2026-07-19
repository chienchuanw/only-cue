import XCTest
@testable import OnlyCue

/// #683 Approach C — writes a plugin bundle's two files into a directory.
final class MA2PluginWriterTests: XCTestCase {

    func test_write_createsBothFilesWithContents() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ma2plugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bundle = MA2PluginBundle(
            luaFilename: "OnlyCue_X_PLUGIN.lua",
            lua: "-- lua",
            manifestFilename: "OnlyCue_X.xml",
            manifestXML: "<MA/>"
        )
        let urls = try MA2PluginWriter.write(bundle, toDirectory: dir)

        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["OnlyCue_X_PLUGIN.lua", "OnlyCue_X.xml"])
        let lua = try String(contentsOf: dir.appendingPathComponent("OnlyCue_X_PLUGIN.lua"), encoding: .utf8)
        let xml = try String(contentsOf: dir.appendingPathComponent("OnlyCue_X.xml"), encoding: .utf8)
        XCTAssertEqual(lua, "-- lua")
        XCTAssertEqual(xml, "<MA/>")
    }
}
