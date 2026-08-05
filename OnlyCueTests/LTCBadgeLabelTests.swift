import XCTest
@testable import OnlyCue

final class LTCBadgeLabelTests: XCTestCase {

    // MARK: Channel-name mapping

    func test_channel1_count2_containsR() {
        let label = LTCBadgeLabel.text(channel: 1, channelCount: 2, startTimecode: "01:00:00:00")
        XCTAssertTrue(label.contains("R"), "expected 'R' in \"\(label)\"")
        XCTAssertTrue(label.contains("LTC"), "expected 'LTC' in \"\(label)\"")
        XCTAssertTrue(label.contains("muted"), "expected 'muted' in \"\(label)\"")
        XCTAssertTrue(label.contains("01:00:00:00"), "expected timecode in \"\(label)\"")
    }

    func test_channel0_count2_containsL() {
        let label = LTCBadgeLabel.text(channel: 0, channelCount: 2, startTimecode: "01:00:00:00")
        XCTAssertTrue(label.contains("L"), "expected 'L' in \"\(label)\"")
        XCTAssertTrue(label.contains("LTC"), "expected 'LTC' in \"\(label)\"")
        XCTAssertTrue(label.contains("muted"), "expected 'muted' in \"\(label)\"")
        XCTAssertTrue(label.contains("01:00:00:00"), "expected timecode in \"\(label)\"")
    }

    func test_channel2_count4_containsCh3() {
        let label = LTCBadgeLabel.text(channel: 2, channelCount: 4, startTimecode: "02:30:15:12")
        XCTAssertTrue(label.contains("Ch 3"), "expected 'Ch 3' in \"\(label)\"")
        XCTAssertTrue(label.contains("LTC"), "expected 'LTC' in \"\(label)\"")
        XCTAssertTrue(label.contains("muted"), "expected 'muted' in \"\(label)\"")
        XCTAssertTrue(label.contains("02:30:15:12"), "expected timecode in \"\(label)\"")
    }

    func test_channel1_nilCount_stillContainsR() {
        // Proves index-based mapping is nil-safe (no channelCount required)
        let label = LTCBadgeLabel.text(channel: 1, channelCount: nil, startTimecode: "00:00:00:00")
        XCTAssertTrue(label.contains("R"), "expected 'R' in \"\(label)\"")
        XCTAssertTrue(label.contains("LTC"), "expected 'LTC' in \"\(label)\"")
        XCTAssertTrue(label.contains("muted"), "expected 'muted' in \"\(label)\"")
    }

    // MARK: Edge cases

    func test_channel0_nilCount_containsL() {
        let label = LTCBadgeLabel.text(channel: 0, channelCount: nil, startTimecode: "12:00:00:00")
        XCTAssertTrue(label.contains("L"), "expected 'L' in \"\(label)\"")
    }

    func test_channel3_nilCount_containsCh4() {
        let label = LTCBadgeLabel.text(channel: 3, channelCount: nil, startTimecode: "00:00:00:00")
        XCTAssertTrue(label.contains("Ch 4"), "expected 'Ch 4' in \"\(label)\"")
    }
}
