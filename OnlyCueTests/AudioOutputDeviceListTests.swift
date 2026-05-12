import XCTest
@testable import OnlyCue

/// Smoke tests for the Core Audio enumeration — they only assert *shape*
/// (non-crashing, internally consistent), not that any particular device
/// exists, so they hold on a developer machine, in CI, and on a headless box.
final class AudioOutputDeviceListTests: XCTestCase {

    func test_current_returnsConsistentDevices() {
        for device in AudioOutputDeviceList.current() {
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertGreaterThan(device.outputChannelCount, 0)
        }
    }

    func test_uids_areUnique() {
        let uids = AudioOutputDeviceList.current().map(\.uid)
        XCTAssertEqual(Set(uids).count, uids.count)
    }

    func test_defaultOutput_ifPresent_isAmongCurrent() {
        guard let output = AudioOutputDeviceList.defaultOutput() else { return }
        XCTAssertTrue(AudioOutputDeviceList.current().map(\.uid).contains(output.uid))
    }
}
