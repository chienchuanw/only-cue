import SwiftUI
import XCTest
@testable import OnlyCue

/// Column-count cap for `WaveformView` (#681). At high horizontal zoom the
/// content width runs to tens of thousands of points; bucketing the ~12k source
/// peaks into that many columns re-draws a ~140k-point path every follow frame
/// and drops frames. The path can carry no more detail than the source peaks, so
/// the column count is capped at the source resolution — lossless, and ~6×
/// cheaper per frame at 64×.
final class WaveformViewBucketCountTests: XCTestCase {

    func test_bucketCount_capsAtSourceResolution_whenWidthExceedsPeaks() {
        // 64× on a 12k-peak clip: width ≫ peaks ⇒ cap at the peak count.
        XCTAssertEqual(WaveformView.bucketCount(width: 70_400, peakCount: 12_000), 12_000)
    }

    func test_bucketCount_usesWidth_whenNarrowerThanPeaks() {
        // Low zoom: fewer on-screen points than source peaks ⇒ downsample to width.
        XCTAssertEqual(WaveformView.bucketCount(width: 1_100, peakCount: 12_000), 1_100)
    }

    func test_bucketCount_roundsWidth() {
        XCTAssertEqual(WaveformView.bucketCount(width: 800.6, peakCount: 12_000), 801)
    }

    func test_bucketCount_isNonNegative_forEmptyOrZero() {
        XCTAssertEqual(WaveformView.bucketCount(width: 0, peakCount: 0), 0)
        XCTAssertEqual(WaveformView.bucketCount(width: 500, peakCount: 0), 0)
    }
}
