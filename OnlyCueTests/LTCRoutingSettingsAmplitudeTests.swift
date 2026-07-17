import XCTest
@testable import OnlyCue

/// #651 — the LTC output level (amplitude) field: clamped to 0...1, persisted,
/// and backward-compatible with settings written before the field existed.
final class LTCRoutingSettingsAmplitudeTests: XCTestCase {

    private func base() -> LTCRoutingSettings {
        LTCRoutingSettings(deviceUID: nil, channelRoles: [])
    }

    func test_defaultAmplitude_isPointNine() {
        XCTAssertEqual(LTCRoutingSettings.defaultAmplitude, 0.9)
    }

    func test_settingAmplitude_clampsBelowZero() {
        XCTAssertEqual(base().settingAmplitude(-0.5).amplitude, 0)
    }

    func test_settingAmplitude_clampsAboveOne() {
        XCTAssertEqual(base().settingAmplitude(1.5).amplitude, 1)
    }

    func test_settingAmplitude_inRangePassesThrough() {
        XCTAssertEqual(base().settingAmplitude(0.6).amplitude, 0.6, accuracy: 1e-6)
    }

    func test_codable_roundTripsAmplitude() throws {
        let settings = base().settingAmplitude(0.55)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: data)
        XCTAssertEqual(decoded.amplitude, 0.55, accuracy: 1e-6)
    }

    func test_decode_missingAmplitude_usesDefault() throws {
        // Settings written before the amplitude field existed.
        let json = #"{"isEnabled":true,"channelRoles":["ltc"]}"#
        let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.amplitude, LTCRoutingSettings.defaultAmplitude)
    }

    func test_decode_outOfRangeAmplitude_clamps() throws {
        let json = #"{"isEnabled":true,"channelRoles":["ltc"],"amplitude":2.0}"#
        let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.amplitude, 1)
    }
}
