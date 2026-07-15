import Foundation

/// Pure planner for Export Bundle (#640): decides the `media/` folder layout for
/// a set of media items whose source files have already been located. Dedupes
/// files shared by multiple items, renames name collisions deterministically,
/// assigns each item its `bundlePath` (`media/<name>`), and lists the items
/// whose file couldn't be located (for the option-C warning). Pure — the impure
/// resolve/copy/write happens in the export action.
struct BundleLayout: Equatable {

    struct Source: Equatable {
        let id: MediaItem.ID
        let name: String
        let url: URL?
    }

    struct Entry: Equatable {
        let source: URL
        let destName: String
        var itemIDs: [MediaItem.ID]
    }

    /// One entry per unique source file; the file is copied to `media/<destName>`.
    let entries: [Entry]
    /// Each resolvable item's `bundlePath`, e.g. `"media/Intro.wav"`.
    let bundlePathByItem: [MediaItem.ID: String]
    /// Items whose source URL was nil (couldn't be located) — the option-C list.
    let missing: [MediaItem.ID]

    static func plan(_ sources: [Source]) -> Self {
        var entries: [Entry] = []
        var bundlePathByItem: [MediaItem.ID: String] = [:]
        var missing: [MediaItem.ID] = []
        var indexBySource: [URL: Int] = [:]
        var usedNames: Set<String> = []

        for source in sources {
            guard let url = source.url else {
                missing.append(source.id)
                continue
            }
            if let idx = indexBySource[url] {
                entries[idx].itemIDs.append(source.id)
                bundlePathByItem[source.id] = "media/" + entries[idx].destName
            } else {
                let destName = uniqueName(source.name, used: &usedNames)
                indexBySource[url] = entries.count
                entries.append(Entry(source: url, destName: destName, itemIDs: [source.id]))
                bundlePathByItem[source.id] = "media/" + destName
            }
        }
        return Self(entries: entries, bundlePathByItem: bundlePathByItem, missing: missing)
    }

    /// A `media/`-unique filename, suffixing `-2`, `-3`, … before the extension
    /// on collision. Deterministic in input order.
    private static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        if used.insert(name).inserted { return name }
        let ns = name as NSString
        let stem = ns.deletingPathExtension
        let ext = ns.pathExtension
        var suffix = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            if used.insert(candidate).inserted { return candidate }
            suffix += 1
        }
    }
}
