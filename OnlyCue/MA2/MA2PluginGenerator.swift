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
