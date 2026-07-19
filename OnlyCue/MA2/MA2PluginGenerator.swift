import Foundation

/// Wraps an `MA2PushPlan` (#683, Approach C) into a grandMA2 Lua plugin that,
/// when run on the console, writes the two XML payloads into the console's own
/// `importexport` folder, imports them via `gma.cmd`, then deletes the temp
/// files — the CuePoints "TC object" pattern, which needs no FTP because the
/// plugin runs on the console. The Lua runtime wrapper (how MA2 invokes the
/// plugin) is modeled on the shared `CuePoints_PLUGIN.lua`; verify plugin
/// invocation on a real console during Phase C validation.
enum MA2PluginGenerator {

    static func lua(plan: MA2PushPlan) -> String {
        var lines: [String] = [
            "-- OnlyCue grandMA2 plugin (generated). Imports a sequence + timecode object.",
            "local function onlycue_import()",
            "  local CMD = gma.cmd",
            "  local slash = package.config:sub(1,1)",
            "  local path = gma.show.getvar('PATH')..slash..'importexport'..slash"
        ]
        lines.append(contentsOf: writeFile(plan.sequenceUpload))
        lines.append(contentsOf: writeFile(plan.timecodeUpload))
        for command in plan.commands {
            // Plan commands never contain single quotes; wrap in a Lua single-quoted string.
            lines.append("  CMD('\(command)')")
        }
        lines.append("  gma.sleep(0.5)")
        lines.append("  os.remove(path..'\(plan.sequenceUpload.filename)')")
        lines.append("  os.remove(path..'\(plan.timecodeUpload.filename)')")
        lines.append("end")
        lines.append("return onlycue_import")
        return lines.joined(separator: "\n")
    }

    private static func writeFile(_ upload: MA2PushPlan.Upload) -> [String] {
        // Long-bracket literal [==[ … ]==] keeps the XML's double quotes intact.
        [
            "  local f = io.open(path..'\(upload.filename)', 'w')",
            "  f:write([==[\(upload.xml)]==])",
            "  f:close()"
        ]
    }
}

/// The two files of a generated grandMA2 plugin (#683, Approach C): the Lua
/// script and its `.xml` manifest that points to it.
struct MA2PluginBundle: Equatable {
    var luaFilename: String
    var lua: String
    var manifestFilename: String
    var manifestXML: String
}

extension MA2PluginGenerator {

    static func bundle(plan: MA2PushPlan, pluginName: String, datetime: String) -> MA2PluginBundle {
        let base = "OnlyCue_" + sanitize(pluginName)
        let luaFilename = base + "_PLUGIN.lua"
        return MA2PluginBundle(
            luaFilename: luaFilename,
            lua: lua(plan: plan),
            manifestFilename: base + ".xml",
            manifestXML: manifestXML(pluginName: pluginName, luaFilename: luaFilename, datetime: datetime)
        )
    }

    static func manifestXML(pluginName: String, luaFilename: String, datetime: String) -> String {
        let escape = MA2SequenceXMLGenerator.escape
        return [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<MA xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
                + "xmlns=\"http://schemas.malighting.de/grandma2/xml/MA\" "
                + "major_vers=\"3\" minor_vers=\"9\" stream_vers=\"60\">",
            "\t<Info datetime=\"\(escape(datetime))\" showfile=\"OnlyCue\" />",
            "\t<Plugin index=\"0\" name=\"\(escape(pluginName))\" luafile=\"\(escape(luaFilename))\" />",
            "</MA>"
        ].joined(separator: "\n")
    }

    /// Filesystem-safe base: replace path separators and colons with `_`.
    private static func sanitize(_ name: String) -> String {
        String(name.map { "/\\:".contains($0) ? "_" : $0 })
    }
}
