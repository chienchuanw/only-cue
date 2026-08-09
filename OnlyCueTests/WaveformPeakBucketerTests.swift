import XCTest
@testable import OnlyCue

final class WaveformPeakBucketerTests: XCTestCase {

    func test_widthEqualToCount_returnsInputUnchanged() {
        let peaks: [Float] = [0.1, 0.9, 0.4, 0.7]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 4), peaks)
    }

    func test_downsample_takesMaxPerBucket() {
        // 8 peaks into 2 buckets -> [max(first 4), max(last 4)]
        let peaks: [Float] = [0.1, 0.5, 0.2, 0.3, 0.9, 0.1, 0.4, 0.2]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 2), [0.5, 0.9])
    }

    func test_unevenDivision_lastBucketAbsorbsRemainder() {
        // 5 peaks into 2 buckets -> ceil(5/2)=3, bucket0=max(peaks[0..<3])=0.8,
        // bucket1=max(peaks[3..<5])=0.9
        let peaks: [Float] = [0.2, 0.8, 0.1, 0.3, 0.9]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 2), [0.8, 0.9])
    }

    func test_widthGreaterThanCount_returnsInputUnchanged() {
        let peaks: [Float] = [0.3, 0.6]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 10), peaks)
    }

    func test_emptyPeaks_returnsEmpty() {
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: [], into: 100), [])
    }

    func test_zeroWidth_returnsEmpty() {
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: [0.1, 0.2], into: 0), [])
    }

    // MARK: - RMS (energy-average) collapse for the dual envelope (#734)

    /// The RMS collapse averages energy within a bucket (√mean(x²)), unlike the
    /// max collapse — a full-scale-square vs sparse-spike bucket must read lower.
    func test_bucketRMS_averagesEnergyNotMax() {
        // One bucket of [1, 0, 0, 0]: max is 1.0, RMS is √(1/4) = 0.5.
        XCTAssertEqual(WaveformPeakBucketer.bucketRMS([1, 0, 0, 0], into: 1)[0], 0.5, accuracy: 1e-6)
    }

    func test_bucketRMS_twoBuckets_perBucketEnergy() {
        // [0.6, 0.8] into 1 -> √((0.36+0.64)/2) = √0.5 ≈ 0.7071.
        XCTAssertEqual(WaveformPeakBucketer.bucketRMS([0.6, 0.8], into: 1)[0], 0.70710677, accuracy: 1e-6)
    }

    func test_bucketRMS_widthGreaterThanCount_returnsInputUnchanged() {
        let values: [Float] = [0.3, 0.6]
        XCTAssertEqual(WaveformPeakBucketer.bucketRMS(values, into: 10), values)
    }

    func test_bucketRMS_empty_and_zeroWidth_returnEmpty() {
        XCTAssertEqual(WaveformPeakBucketer.bucketRMS([], into: 4), [])
        XCTAssertEqual(WaveformPeakBucketer.bucketRMS([0.1, 0.2], into: 0), [])
    }
}
