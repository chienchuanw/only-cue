import XCTest
@testable import OnlyCue

final class LTCRoutingSettingsTests: XCTestCase {

    func test_default_isEmptyAndFollowsSystemOutput() {
        let settings = LTCRoutingSettings.default
        XCTAssertNil(settings.deviceUID)
        XCTAssertTrue(settings.channelRoles.isEmpty)
        XCTAssertTrue(settings.ltcChannels.isEmpty)
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

    func test_assigning_sameRole_toSecondChannel_keepsBoth() {
        // #655 — a role may sit on several channels; assigning no longer clears
        // the role off the channel that already had it.
        let settings = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc, .trackLeft, .trackRight, .silent])
        let fanned = settings.assigning(.ltc, toChannel: 3)
        XCTAssertEqual(fanned.channelRoles, [.ltc, .trackLeft, .trackRight, .ltc])
        XCTAssertEqual(fanned.ltcChannels, [0, 3])
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

    func test_default_isDisabled() {
        XCTAssertFalse(LTCRoutingSettings.default.isEnabled)
    }

    func test_isComplete_requiresEnabledAndLTCChannel() {
        XCTAssertFalse(LTCRoutingSettings(isEnabled: false, deviceUID: nil, channelRoles: [.ltc, .trackLeft]).isComplete)
        XCTAssertFalse(LTCRoutingSettings(isEnabled: true, deviceUID: nil, channelRoles: [.silent, .trackLeft]).isComplete)
        XCTAssertTrue(LTCRoutingSettings(isEnabled: true, deviceUID: nil, channelRoles: [.ltc, .trackLeft]).isComplete)
    }

    func test_settingEnabled_togglesOutput_keepsRouting() {
        let settings = LTCRoutingSettings(deviceUID: "uid", channelRoles: [.ltc, .trackLeft])
        let enabled = settings.settingEnabled(true)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(enabled.deviceUID, "uid")
        XCTAssertEqual(enabled.channelRoles, [.ltc, .trackLeft])
        XCTAssertFalse(enabled.settingEnabled(false).isEnabled)
    }

    func test_trackChannels() {
        let none = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc, .silent])
        XCTAssertTrue(none.trackLeftChannels.isEmpty)
        XCTAssertTrue(none.trackRightChannels.isEmpty)
        XCTAssertFalse(none.hasTrackChannels)

        let both = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc, .trackLeft, .trackRight])
        XCTAssertEqual(both.trackLeftChannels, [1])
        XCTAssertEqual(both.trackRightChannels, [2])
        XCTAssertTrue(both.hasTrackChannels)

        let onlyRight = LTCRoutingSettings(deviceUID: nil, channelRoles: [.ltc, .silent, .trackRight])
        XCTAssertTrue(onlyRight.trackLeftChannels.isEmpty)
        XCTAssertEqual(onlyRight.trackRightChannels, [2])
        XCTAssertTrue(onlyRight.hasTrackChannels)
    }

    func test_multipleChannels_perRole() {
        // #655 — LTC and track roles fan out to several channels, in order.
        let settings = LTCRoutingSettings(
            deviceUID: nil, channelRoles: [.ltc, .trackLeft, .ltc, .trackLeft])
        XCTAssertEqual(settings.ltcChannels, [0, 2])
        XCTAssertEqual(settings.trackLeftChannels, [1, 3])
        XCTAssertTrue(settings.channels(for: .trackRight).isEmpty)
    }

    func test_transforms_carryIsEnabled() {
        let settings = LTCRoutingSettings(isEnabled: true, deviceUID: "uid", channelRoles: [.ltc, .trackLeft, .silent])
        XCTAssertTrue(settings.assigning(.trackRight, toChannel: 2).isEnabled)
        XCTAssertTrue(settings.selectingDevice(uid: "other").isEnabled)
        XCTAssertTrue(settings.resized(toChannelCount: 5).isEnabled)
        XCTAssertTrue(settings.withDefaultRoles(forChannelCount: 3).isEnabled)
    }

    func test_codable_missingIsEnabledKey_decodesAsDisabled() throws {
        let legacy = Data(#"{"channelRoles":["ltc","trackLeft"]}"#.utf8)
        let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: legacy)
        XCTAssertFalse(decoded.isEnabled)
        XCTAssertEqual(decoded.channelRoles, [.ltc, .trackLeft])
        XCTAssertNil(decoded.deviceUID)
    }

    func test_codableRoundTrip() throws {
        let original = LTCRoutingSettings(
            isEnabled: true, deviceUID: "Built-in Output", channelRoles: [.ltc, .trackLeft, .trackRight, .silent])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_channelRole_displayNames() {
        XCTAssertEqual(ChannelRole.silent.displayName, "Silent")
        XCTAssertEqual(ChannelRole.ltc.displayName, "LTC")
        XCTAssertEqual(ChannelRole.trackLeft.displayName, "Track L")
        XCTAssertEqual(ChannelRole.trackRight.displayName, "Track R")
    }
}
