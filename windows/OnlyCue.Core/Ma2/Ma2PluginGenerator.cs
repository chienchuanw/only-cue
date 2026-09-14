namespace OnlyCue.Core.Ma2;

/// <summary>
/// The two files of a generated grandMA2 plugin (#683, Approach C): the Lua
/// script and its <c>.xml</c> manifest that points to it. Mirrors Swift
/// <c>MA2PluginBundle</c>.
/// </summary>
public sealed record Ma2PluginBundle(
    string LuaFilename,
    string Lua,
    string ManifestFilename,
    string ManifestXml);

/// <summary>
/// Wraps an <see cref="Ma2PushPlan"/> into a grandMA2 Lua plugin that, when run
/// on the console, writes the two XML payloads into the console's own
/// <c>importexport</c> folder, imports them via <c>gma.cmd</c>, then deletes the
/// temp files — the CuePoints "TC object" pattern, which needs no FTP because the
/// plugin runs on the console. Mirrors Swift <c>MA2PluginGenerator</c>.
/// </summary>
public static class Ma2PluginGenerator
{
    public static Ma2PluginBundle Bundle(Ma2PushPlan plan, string pluginName, string datetime)
    {
        var baseName = "OnlyCue_" + Sanitize(pluginName);
        var luaFilename = baseName + "_PLUGIN.lua";
        return new Ma2PluginBundle(
            luaFilename,
            Lua(plan),
            baseName + ".xml",
            ManifestXml(pluginName, luaFilename, datetime));
    }

    public static string Lua(Ma2PushPlan plan)
    {
        var lines = new List<string>
        {
            "-- OnlyCue grandMA2 plugin (generated). Imports a sequence + timecode object.",
            "local function onlycue_import()",
            "  local CMD = gma.cmd",
            "  local slash = package.config:sub(1,1)",
            "  local path = gma.show.getvar('PATH')..slash..'importexport'..slash"
        };

        lines.AddRange(WriteFile(plan.SequenceUpload));
        lines.AddRange(WriteFile(plan.TimecodeUpload));

        foreach (var command in plan.Commands)
        {
            // Names (e.g. "Don't Stop") reach here via Label commands, so the
            // command can contain apostrophes — escape for the single-quoted
            // Lua string.
            lines.Add($"  CMD({LuaSingleQuoted(command)})");
        }

        lines.Add("  gma.sleep(0.5)");
        lines.Add($"  os.remove(path..'{plan.SequenceUpload.Filename}')");
        lines.Add($"  os.remove(path..'{plan.TimecodeUpload.Filename}')");
        lines.Add("end");
        lines.Add("return onlycue_import");
        return string.Join('\n', lines);
    }

    public static string ManifestXml(string pluginName, string luaFilename, string datetime)
    {
        var escape = Ma2SequenceXmlGenerator.Escape;
        return string.Join('\n', [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<MA xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
                + "xmlns=\"http://schemas.malighting.de/grandma2/xml/MA\" "
                + "major_vers=\"3\" minor_vers=\"9\" stream_vers=\"60\">",
            $"\t<Info datetime=\"{escape(datetime)}\" showfile=\"OnlyCue\" />",
            $"\t<Plugin index=\"0\" name=\"{escape(pluginName)}\" luafile=\"{escape(luaFilename)}\" />",
            "</MA>"
        ]);
    }

    private static List<string> WriteFile(Ma2PushPlan.Upload upload) =>
    [
        $"  local f = io.open(path..'{upload.Filename}', 'w')",
        $"  f:write({LuaLongBracket(upload.Xml)})",
        "  f:close()"
    ];

    /// <summary>
    /// A Lua single-quoted string literal, escaping <c>\</c> and <c>'</c> so a
    /// command carrying an apostrophe can't break the plugin. Commands are
    /// single-line.
    /// </summary>
    /// <remarks>The backslash replacement must come first, or it would double the
    /// backslashes the apostrophe replacement just introduced.</remarks>
    private static string LuaSingleQuoted(string value)
    {
        var escaped = value.Replace("\\", "\\\\").Replace("'", "\\'");
        return $"'{escaped}'";
    }

    /// <summary>
    /// A Lua long-bracket string literal (<c>[==[ … ]==]</c>) whose <c>=</c> level
    /// is raised until the content no longer contains the matching closing
    /// sequence — airtight for multi-line XML (which always ends in <c>&gt;</c>, so
    /// the boundary never produces a stray <c>]</c>). Defaults to level 2 so
    /// ordinary content renders unchanged.
    /// </summary>
    private static string LuaLongBracket(string value)
    {
        var level = 2;
        while (value.Contains("]" + new string('=', level) + "]", StringComparison.Ordinal))
        {
            level++;
        }

        var eq = new string('=', level);
        return $"[{eq}[{value}]{eq}]";
    }

    /// <summary>Filesystem-safe base: replace path separators and colons with
    /// <c>_</c>.</summary>
    private static string Sanitize(string name) =>
        string.Concat(name.Select(character => "/\\:".Contains(character, StringComparison.Ordinal) ? '_' : character));
}
