import AVFoundation
import CoreGraphics

enum VideoPosterError: Error, Equatable {
    case generationFailed
}

enum VideoPosterGenerator {

    /// Poster capture point: 10% into the clip (skips likely-black lead-in),
    /// clamped to >= 0 so sub-second / zero / negative durations are safe.
    static func captureTime(forDurationSeconds seconds: Double) -> CMTime {
        let clamped = max(seconds, 0) * 0.1
        return CMTime(seconds: clamped, preferredTimescale: 600)
    }

    /// Decodes a single representative frame. `maxPixelSize` caps the larger
    /// edge so cached posters stay small. Throws `.generationFailed` on any
    /// AVFoundation error (no video track, undecodable, etc.).
    static func poster(for asset: AVAsset, maxPixelSize: CGFloat = 512) async throws -> CGImage {
        let seconds: Double
        if let duration = try? await asset.load(.duration) {
            seconds = CMTimeGetSeconds(duration)
        } else {
            seconds = 0
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        do {
            let (image, _) = try await generator.image(at: captureTime(forDurationSeconds: seconds))
            return image
        } catch {
            throw VideoPosterError.generationFailed
        }
    }
}
