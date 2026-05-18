import CoreGraphics
import XCTest
@testable import OnlyCue

final class VideoPosterCacheTests: XCTestCase {

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    private func makeIsolatedCache() -> VideoPosterCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poster-cache-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return VideoPosterCache(directory: directory)
    }

    func test_writeThenRead_roundTripsImageDimensions() throws {
        let cache = makeIsolatedCache()
        let image = try makeImage(width: 64, height: 48)
        try cache.write(image, assetHash: "abc", maxPixelSize: 512)

        let recovered = cache.read(assetHash: "abc", maxPixelSize: 512)

        XCTAssertEqual(recovered?.width, 64)
        XCTAssertEqual(recovered?.height, 48)
    }

    func test_read_missingEntry_returnsNil() {
        XCTAssertNil(makeIsolatedCache().read(assetHash: "nope", maxPixelSize: 512))
    }

    func test_read_sizeMismatch_returnsNil() throws {
        let cache = makeIsolatedCache()
        let image = try makeImage(width: 10, height: 10)
        try cache.write(image, assetHash: "h1", maxPixelSize: 256)

        XCTAssertNil(cache.read(assetHash: "h1", maxPixelSize: 512))
    }
}
