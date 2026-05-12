import XCTest
@testable import OnlyCue

final class LTCRoutingSettingsTests: XCTestCase {

    func test_default_isEmptyAndFollowsSystemOutput() {
        let settings = LTCRoutingSettings.default
        XCTAssertNil(settings.deviceUID)
        XCTAssertTrue(settings.channelRoles.isEmpty)
        XCTAssertNil(settings.ltcChannel)
        XCTAssertFalse(settings.isComplete)
    }

    func test_roleForChannel_outOfRange_isSilent() {
        let settings = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc, .trackLeft])
        XCTAssertEqual(settings.role(forChannel: 0), .ltc)
        XCTAssertEqual(settings.role(forChannel: 1), .trackLeft)
        XCTAssertEqual(settings.role(forChannel: 2), .silent)
        XCTAssertEqual(settings.role(forChannel: -1), .silent)
    }

    func test_defaultRoles_layout() {
        XCTAssertEqual(LTCRoutingSettings.defaultRoles(forChannelCount: 4), [.ltc, .trackLeft, .trackRight, .silent])
        XCTAssertEqual(LTCRoutingSettings.defaultRoles(forChannelCount: 2), [.ltc, .trackLeft])
        XCTAssertEqual(LTCRoutingSettings.defaultRoles(forChannelCount: 1), [.ltc])
        XCTAssertEqual(LTCRoutingSettings.defaultRoles(forChannelCount: 0), [])
        XCTAssertEqual(LTCRoutingSettings.defaultRoles(forChannelCount: -3), [])
    }

    func test_assigning_uniqueRole_clearsPreviousHolder() {
        let settings = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc, .trackLeft, .trackRight, .silent])
        let moved = settings.assigning(.ltc, toChannel: 3)
        XCTAssertEqual(moved.channelRoles, [.silent, .trackLeft, .trackRight, .ltc])
        XCTAssertEqual(moved.ltcChannel, 3)
    }

    func test_assigning_silent_doesNotClearOtherSilents() {
        let settings = LTCRoutingSettings(deviceUID: nil, channelRoles: [.silent, .silent, .ltc])
        let updated = settings.assigning(.silent, toChannel: 2)
        XCTAssertEqual(updated.channelRoles, [.silent, .silent, .silent])
    }

    func test_assigning_outOfRangeChannel_isNoOp() {
        let settings = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc])
        XCTAssertEqual(settings.assigning(.trackLeft, toChannel: 5), settings)
    }

    func test_resized_padsWithSilentAndTruncates() {
        let settings = LTCRoutingSettings(deviceUID: "uid", channelRoles: [.ltc, .trackLeft])
        XCTAssertEqual(settings.resized(toChannelCount: 4).channelRoles, [.ltc, .trackLeft, .silent, .silent])
        XCTAssertEqual(settings.resized(toChannelCount: 1).channelRoles, [.ltc])
        XCTAssertEqual(settings.resized(toChannelCount: 0).channelRoles, [])
        XCTAssertEqual(settings.resized(toChannelCount: -2).channelRoles, [])
        XCTAssertEqual(settings.resized(toChannelCount: 2).deviceUID, "uid")
    }

    func test_withDefaultRoles_replacesLayout_keepsDevice() {
        let settings = LTCRoutingSettings(deviceUID: "uid", channelRoles: [.silent, .silent])
        let defaulted = settings.withDefaultRoles(forChannelCount: 3)
        XCTAssertEqual(defaulted.channelRoles, [.ltc, .trackLeft, .trackRight])
        XCTAssertEqual(defaulted.deviceUID, "uid")
    }

    func test_selectingDevice_keepsChannelRoles() {
        let settings = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc, .trackLeft])
        let updated = settings.selectingDevice(uid: "abc")
        XCTAssertEqual(updated.deviceUID, "abc")
        XCTAssertEqual(updated.channelRoles, [.ltc, .trackLeft])
    }

    func test_isComplete_requiresLTCChannel() {
        XCTAssertFalse(LTCRoutingSettings(deviceUID: nil, channelRoles: [.trackLeft, .trackRight]).isComplete)
        XCTAssertTrue(LTCRoutingSettings(deviceUID: nil, channelRoles: [.silent, .ltc]).isComplete)
    }

    func test_codableRoundTrip() throws {
        let original = LTCRoutingSettings(deviceUID: "Built-in Output", channelRoles: [.ltc, .trackLeft, .trackRight, .silent])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_channelRole_displayNamesAndUniqueness() {
        XCTAssertEqual(ChannelRole.silent.displayName, "Silent")
        XCTAssertEqual(ChannelRole.ltc.displayName, "LTC")
        XCTAssertFalse(ChannelRole.silent.isUnique)
        XCTAssertTrue(ChannelRole.ltc.isUnique)
        XCTAssertTrue(ChannelRole.trackLeft.isUnique)
        XCTAssertTrue(ChannelRole.trackRight.isUnique)
    }
}
