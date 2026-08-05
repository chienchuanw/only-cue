import CryptoKit
import Foundation

struct WaveformCache {

    let directory: URL

    static let shared: WaveformCache = {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return Self(directory: base.appendingPathComponent("OnlyCue/peaks", isDirectory: true))
    }()

    func read(assetHash: String, resolution: Int, excludingChannel: Int? = nil) -> [Float]? {
        let url = entryURL(assetHash: assetHash, resolution: resolution, excludingChannel: excludingChannel)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let count = data.count / MemoryLayout<Float32>.size
        guard count == resolution else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float32.self))
        }
    }

    func read(assetHash: String, resolution: Int, channel: Int) -> [Float]? {
        let url = entryURL(assetHash: assetHash, resolution: resolution, channel: channel)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let count = data.count / MemoryLayout<Float32>.size
        guard count == resolution else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float32.self))
        }
    }

    func write(_ peaks: [Float], assetHash: String, resolution: Int, excludingChannel: Int? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = peaks.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try data.write(
            to: entryURL(assetHash: assetHash, resolution: resolution, excludingChannel: excludingChannel),
            options: .atomic
        )
    }

    func write(_ peaks: [Float], assetHash: String, resolution: Int, channel: Int) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = peaks.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try data.write(
            to: entryURL(assetHash: assetHash, resolution: resolution, channel: channel),
            options: .atomic
        )
    }

    /// Bumped to v2 when peaks became per-file normalized (issue #538), and to
    /// v3 when the envelope became per-bucket RMS energy rather than peak (issue
    /// #632). The version is part of the cache key so previously-cached peak
    /// arrays are ignored and regenerated as RMS rather than served stale.
    private static let formatVersion = 3

    /// Internal (not private) so tests can locate a specific cache entry without
    /// hard-coding the on-disk filename format (which embeds `formatVersion`).
    ///
    /// When `excludingChannel` is non-nil the filename includes an `xc<N>` suffix
    /// so a music-only render (e.g. `xc1` = "exclude channel 1") never collides
    /// with the all-channel downmix entry for the same file and resolution.
    func entryURL(assetHash: String, resolution: Int, excludingChannel: Int? = nil) -> URL {
        let channelSuffix = excludingChannel.map { "-xc\($0)" } ?? ""
        return directory.appendingPathComponent(
            "\(assetHash)-\(resolution)\(channelSuffix)-v\(Self.formatVersion).peaks"
        )
    }

    /// Overload for per-channel peak arrays. The `-ch<N>` suffix is distinct
    /// from the `-xc<N>` (excludingChannel) suffix and from the combined key,
    /// so channel 0 peaks, music-only (xc0) peaks, and the downmix never collide.
    func entryURL(assetHash: String, resolution: Int, channel: Int) -> URL {
        directory.appendingPathComponent(
            "\(assetHash)-\(resolution)-ch\(channel)-v\(Self.formatVersion).peaks"
        )
    }

    static func fileHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
