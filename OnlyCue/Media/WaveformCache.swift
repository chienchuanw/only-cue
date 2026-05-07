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

    func read(assetHash: String, resolution: Int) -> [Float]? {
        let url = entryURL(assetHash: assetHash, resolution: resolution)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let count = data.count / MemoryLayout<Float32>.size
        guard count == resolution else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float32.self))
        }
    }

    func write(_ peaks: [Float], assetHash: String, resolution: Int) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = peaks.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try data.write(to: entryURL(assetHash: assetHash, resolution: resolution), options: .atomic)
    }

    private func entryURL(assetHash: String, resolution: Int) -> URL {
        directory.appendingPathComponent("\(assetHash)-\(resolution).peaks")
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
