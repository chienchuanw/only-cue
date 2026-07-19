import XCTest
@testable import OnlyCue

/// #683 Approach C — the generated grandMA2 Lua plugin (local write + import + cleanup).
final class MA2PluginGeneratorTests: XCTestCase {

    private func plan() -> MA2PushPlan {
        MA2PushPlan(
            sequenceUpload: .init(filename: "onlycue_seq_900.xml", xml: "<seq/>"),
            timecodeUpload: .init(filename: "onlycue_tc_9.xml", xml: "<tc/>"),
            commands: ["Delete Sequence 900 /nc", "Import \"onlycue_seq_900\" At 900 /nc"]
        )
    }

    func test_lua_writesBothFilesLocally_runsCommands_thenRemoves() {
        let lua = MA2PluginGenerator.lua(plan: plan())
        // Resolves the console's local importexport folder + OS path separator.
        XCTAssertTrue(lua.contains("gma.show.getvar('PATH')"))
        XCTAssertTrue(lua.contains("package.config:sub(1,1)"))
        // Writes each payload with a long-bracket literal so XML quotes survive.
        XCTAssertTrue(lua.contains("'onlycue_seq_900.xml'"))
        XCTAssertTrue(lua.contains("[==[<seq/>]==]"))
        XCTAssertTrue(lua.contains("'onlycue_tc_9.xml'"))
        XCTAssertTrue(lua.contains("[==[<tc/>]==]"))
        // Runs each plan command via gma.cmd.
        XCTAssertTrue(lua.contains("CMD('Delete Sequence 900 /nc')"))
        XCTAssertTrue(lua.contains("CMD('Import \"onlycue_seq_900\" At 900 /nc')"))
        // Cleans up both temp files.
        XCTAssertTrue(lua.contains("os.remove(path..'onlycue_seq_900.xml')"))
        XCTAssertTrue(lua.contains("os.remove(path..'onlycue_tc_9.xml')"))
    }

    func test_bundle_pairsLuaWithManifestPointingToIt() {
        let bundle = MA2PluginGenerator.bundle(
            plan: plan(),
            pluginName: "Opening",
            datetime: "2026-07-20T00:00:00"
        )
        XCTAssertEqual(bundle.luaFilename, "OnlyCue_Opening_PLUGIN.lua")
        XCTAssertEqual(bundle.manifestFilename, "OnlyCue_Opening.xml")
        XCTAssertTrue(bundle.manifestXML.contains("<Plugin"))
        XCTAssertTrue(bundle.manifestXML.contains("luafile=\"OnlyCue_Opening_PLUGIN.lua\""))
        XCTAssertTrue(bundle.manifestXML.contains("datetime=\"2026-07-20T00:00:00\""))
        XCTAssertEqual(bundle.lua, MA2PluginGenerator.lua(plan: plan()))
    }

    func test_bundle_sanitizesPluginNameForFilenames() {
        let bundle = MA2PluginGenerator.bundle(plan: plan(), pluginName: "A / B: c", datetime: "d")
        XCTAssertFalse(bundle.luaFilename.contains("/"))
        XCTAssertFalse(bundle.luaFilename.contains(":"))
    }

    func test_lua_escapesApostrophesInCommands_forValidLua() {
        // A song title like "Don't Stop" flows into a Label command; an
        // unescaped ' would close the CMD('…') Lua string and break the plugin.
        let planWithApostrophe = MA2PushPlan(
            sequenceUpload: .init(filename: "s.xml", xml: "<s/>"),
            timecodeUpload: .init(filename: "t.xml", xml: "<t/>"),
            commands: ["Label Sequence 1 \"Don't Stop\""]
        )
        let lua = MA2PluginGenerator.lua(plan: planWithApostrophe)
        XCTAssertTrue(lua.contains("CMD('Label Sequence 1 \"Don\\'t Stop\"')"))
        XCTAssertFalse(lua.contains("CMD('Label Sequence 1 \"Don't Stop\"')"))
    }

    func test_lua_bumpsLongBracketLevel_whenXmlContainsClosingSequence() {
        // A name yielding "]==]" inside the XML must not close the [==[ … ]==] literal.
        let planWithBracket = MA2PushPlan(
            sequenceUpload: .init(filename: "s.xml", xml: "a]==]b"),
            timecodeUpload: .init(filename: "t.xml", xml: "<t/>"),
            commands: []
        )
        let lua = MA2PluginGenerator.lua(plan: planWithBracket)
        XCTAssertTrue(lua.contains("[===[a]==]b]===]"))
    }
}
