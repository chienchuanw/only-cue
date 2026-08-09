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

    // MARK: - Bucket cache (v4, #732/#734)

    /// Buckets store two un-normalized Float32s each (peak, rms) at a time-based
    /// resolution. v4 is the sole on-disk format since #734 retired the legacy
    /// pre-normalized `[Float]` peaks cache (v1–v3). The `bv` filename token is
    /// kept so the v4 bucket entries written during the #729 rollout stay valid.
    private static let bucketFormatVersion = 4

    /// Reads the cached bucket array for `bucketMillis`, or nil on a miss or a
    /// corrupt (non-whole-bucket) file.
    func readBuckets(assetHash: String, bucketMillis: Int, excludingChannel: Int? = nil) -> [WaveformBucket]? {
        readBuckets(at: bucketEntryURL(assetHash: assetHash, bucketMillis: bucketMillis, excludingChannel: excludingChannel))
    }

    func readBuckets(assetHash: String, bucketMillis: Int, channel: Int) -> [WaveformBucket]? {
        readBuckets(at: bucketEntryURL(assetHash: assetHash, bucketMillis: bucketMillis, channel: channel))
    }

    func writeBuckets(_ buckets: [WaveformBucket], assetHash: String, bucketMillis: Int, excludingChannel: Int? = nil) throws {
        try writeBuckets(buckets, to: bucketEntryURL(assetHash: assetHash, bucketMillis: bucketMillis, excludingChannel: excludingChannel))
    }

    func writeBuckets(_ buckets: [WaveformBucket], assetHash: String, bucketMillis: Int, channel: Int) throws {
        try writeBuckets(buckets, to: bucketEntryURL(assetHash: assetHash, bucketMillis: bucketMillis, channel: channel))
    }

    /// `-<ms>ms` encodes the time-based resolution; `-xc<N>` / `-ch<N>` mirror the
    /// legacy peaks keys so a music-only, per-channel, and downmix bucket entry
    /// never collide. `.buckets` distinguishes the two-value format from `.peaks`.
    func bucketEntryURL(assetHash: String, bucketMillis: Int, excludingChannel: Int? = nil) -> URL {
        let channelSuffix = excludingChannel.map { "-xc\($0)" } ?? ""
        return directory.appendingPathComponent(
            "\(assetHash)-\(bucketMillis)ms\(channelSuffix)-bv\(Self.bucketFormatVersion).buckets"
        )
    }

    func bucketEntryURL(assetHash: String, bucketMillis: Int, channel: Int) -> URL {
        directory.appendingPathComponent(
            "\(assetHash)-\(bucketMillis)ms-ch\(channel)-bv\(Self.bucketFormatVersion).buckets"
        )
    }

    private func readBuckets(at url: URL) -> [WaveformBucket]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let stride = 2 * MemoryLayout<Float32>.size
        guard data.count % stride == 0 else { return nil }
        return data.withUnsafeBytes { raw -> [WaveformBucket] in
            let floats = raw.bindMemory(to: Float32.self)
            var result: [WaveformBucket] = []
            result.reserveCapacity(floats.count / 2)
            var index = 0
            while index + 1 < floats.count {
                result.append(WaveformBucket(peak: floats[index], rms: floats[index + 1]))
                index += 2
            }
            return result
        }
    }

    private func writeBuckets(_ buckets: [WaveformBucket], to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var floats: [Float32] = []
        floats.reserveCapacity(buckets.count * 2)
        for bucket in buckets {
            floats.append(bucket.peak)
            floats.append(bucket.rms)
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url, options: .atomic)
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
