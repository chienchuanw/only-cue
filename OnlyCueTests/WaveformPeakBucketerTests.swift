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
}
