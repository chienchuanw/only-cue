import Foundation

/// Writes an `MA2PluginBundle`'s two files into a user-chosen directory
/// (#683, Approach C). Pure filesystem — the `NSSavePanel` picks the directory.
enum MA2PluginWriter {
    @discardableResult
    static func write(_ bundle: MA2PluginBundle, toDirectory directory: URL) throws -> [URL] {
        let luaURL = directory.appendingPathComponent(bundle.luaFilename)
        let xmlURL = directory.appendingPathComponent(bundle.manifestFilename)
        try bundle.lua.write(to: luaURL, atomically: true, encoding: .utf8)
        try bundle.manifestXML.write(to: xmlURL, atomically: true, encoding: .utf8)
        return [luaURL, xmlURL]
    }
}
