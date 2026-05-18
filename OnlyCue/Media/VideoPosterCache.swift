import AppKit
import CoreGraphics
import Foundation

/// PNG disk cache for video poster frames. Mirrors `WaveformCache`: keyed by
/// source-file SHA256 (reuse `WaveformCache.fileHash`) plus the max pixel size.
struct VideoPosterCache {

    let directory: URL

    static let shared: VideoPosterCache = {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return Self(directory: base.appendingPathComponent("OnlyCue/posters", isDirectory: true))
    }()

    func read(assetHash: String, maxPixelSize: Int) -> CGImage? {
        let url = entryURL(assetHash: assetHash, maxPixelSize: maxPixelSize)
        guard let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }

    func write(_ image: CGImage, assetHash: String, maxPixelSize: Int) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: entryURL(assetHash: assetHash, maxPixelSize: maxPixelSize), options: .atomic)
    }

    private func entryURL(assetHash: String, maxPixelSize: Int) -> URL {
        directory.appendingPathComponent("\(assetHash)-\(maxPixelSize).png")
    }
}
