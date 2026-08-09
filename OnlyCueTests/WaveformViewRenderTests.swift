import AppKit
import SwiftUI
import XCTest
@testable import OnlyCue

/// Renders the real `WaveformView` off-screen (SwiftUI `ImageRenderer`) on
/// brickwall-loud data — the condition that made the dual-envelope peak layer
/// saturate the well into a solid grey slab clamped against the top/bottom
/// edges (#739). The peak layer must stay a FAINT two-tone fill (a soft halo
/// around the RMS body) with visible headroom, not a full-strength slab.
@MainActor
final class WaveformViewRenderTests: XCTestCase {

    /// Brickwall-loud buckets: peaks pinned near full-scale across the whole
    /// span, RMS well below peak — exactly what a limited master looks like.
    private func loudBuckets(count: Int) -> [WaveformBucket] {
        (0..<count).map { index in
            let phase = Double(index) * 0.5
            let peak = Float(0.95 + 0.05 * abs(sin(phase)))          // ~0.95…1.0
            let rms = Float(0.44 + 0.03 * abs(sin(phase * 0.5)))     // ~0.44…0.47
            return WaveformBucket(peak: peak, rms: min(rms, peak))
        }
    }

    func test_loudTrack_peakLayerIsFaintTwoTone_withHeadroom() throws {
        let image = try render(
            WaveformView(buckets: loudBuckets(count: 600)),
            size: CGSize(width: 800, height: 240)
        )

        // Three vertical zones for this data (midY = 120):
        //   • top edge  y≈3…10  — above the peak: must be background (headroom).
        //   • peak band y≈45…60 — the peak fill ABOVE the RMS body: must be a
        //     FAINT two-tone grey, not a full-strength slab.
        //   • body      y≈108…132 — the opaque RMS body: brightest.
        let topEdge = meanLuminance(image, rect: CGRect(x: 300, y: 3, width: 200, height: 7))
        let peakBand = meanLuminance(image, rect: CGRect(x: 300, y: 45, width: 200, height: 15))
        let body = meanLuminance(image, rect: CGRect(x: 300, y: 108, width: 200, height: 24))

        XCTAssertLessThan(topEdge, 0.15, "the loudest peak must leave visible headroom, not touch the top edge")
        XCTAssertGreaterThan(peakBand, 0.15, "the peak layer must still be visible above the body (two-tone)")
        XCTAssertLessThan(
            peakBand,
            0.33,
            "the peak fill must be a FAINT halo, not a full-strength slab (measured \(peakBand))"
        )
        XCTAssertGreaterThan(body, peakBand + 0.20, "the RMS body must clearly lead the fainter peak layer")

        attachReviewRender()
    }

    // MARK: - Visual review artifact

    /// Attaches a realistic loud-with-gaps render (and drops a PNG under the temp
    /// dir) so the dual-envelope look can be eyeballed in the result bundle.
    private func attachReviewRender() {
        guard let image = try? render(
            WaveformView(buckets: reviewBuckets()),
            size: CGSize(width: 1400, height: 320),
            scale: 2
        ), let png = try? pngData(image) else { return }

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "waveform-dual-envelope"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Realistic material resembling a full loud track zoomed out: near-flat
    /// full-scale peaks, an RMS body well below peak, periodic near-silent gaps,
    /// and one quieter passage in the middle.
    private func reviewBuckets() -> [WaveformBucket] {
        (0..<1400).map { index in
            if index % 130 < 9 {
                return WaveformBucket(peak: 0.03, rms: 0.01)
            }
            let x = Double(index)
            let calm = (index > 520 && index < 780) ? 0.5 : 1.0
            let peak = min(1.0, (0.93 + 0.05 * sin(x * 0.02)) * calm)
            let rms = min(peak, (0.16 + 0.14 * abs(sin(x * 0.03))) * calm)
            return WaveformBucket(peak: Float(peak), rms: Float(rms))
        }
    }

    // MARK: - Render helpers

    private func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 1) throws -> CGImage {
        // Opaque dark surface + dark scheme, mirroring the dark-only document
        // window (ADR-029) so the achromatic waveform reads as in the app.
        let content = ZStack {
            Color(white: 0.07)
            view
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = true
        return try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no image")
    }

    /// Mean relative luminance (0…1) over `rect` (pixel space at scale 1),
    /// redrawing into a fixed RGBA8 context so channel order is deterministic.
    private func meanLuminance(_ image: CGImage, rect: CGRect) -> Double {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0.0
        var samples = 0
        let minX = max(0, Int(rect.minX)), maxX = min(width, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(height, Int(rect.maxY))
        for pixelY in minY..<maxY {
            for pixelX in minX..<maxX {
                let offset = (pixelY * width + pixelX) * 4
                let red = Double(buffer[offset])
                let green = Double(buffer[offset + 1])
                let blue = Double(buffer[offset + 2])
                sum += (0.299 * red + 0.587 * green + 0.114 * blue) / 255
                samples += 1
            }
        }
        return samples > 0 ? sum / Double(samples) : 0
    }

    private func pngData(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]), "PNG encode failed")
    }
}
