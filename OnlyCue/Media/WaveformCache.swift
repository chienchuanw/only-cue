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

    /// Bytes read from each end of the file for the fingerprint (1 MB).
    private static let fingerprintChunk = 1 << 20

    /// A cache key that identifies a media file in **constant time**, regardless
    /// of size: the byte length plus a SHA256 of the first and last 1 MB. Unlike
    /// a full-file hash, a 50 GB import is fingerprinted without reading 50 GB.
    ///
    /// Deliberately excludes mtime — a `touch` that leaves content unchanged must
    /// not invalidate the cache. The accepted tradeoff (spec §1, user-signed-off):
    /// two files with identical size + identical head/tail but a differing middle
    /// collide; for real media files this is effectively impossible (re-encoding
    /// changes size, editing changes head/tail), and there is no manual-regenerate
    /// escape hatch by design.
    static func fastFingerprint(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()

        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }

        let chunk = fingerprintChunk
        if size <= UInt64(2 * chunk) {
            // Head and tail would overlap — just hash the whole (small) file.
            try handle.seek(toOffset: 0)
            if let all = try handle.readToEnd() { hasher.update(data: all) }
        } else {
            try handle.seek(toOffset: 0)
            hasher.update(data: handle.readData(ofLength: chunk))
            try handle.seek(toOffset: size - UInt64(chunk))
            hasher.update(data: handle.readData(ofLength: chunk))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
