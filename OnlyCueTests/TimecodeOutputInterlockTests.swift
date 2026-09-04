import XCTest
@testable import OnlyCue

/// The off-speed-playback interlock (epic #794).
///
/// Both timecode generators free-run at the nominal rate, so playing at anything
/// other than 1.0× would emit timecode that no longer describes the media. LTC
/// has always blocked this; MTC has exactly the same property, so the gate is
/// about *timecode output* rather than about LTC specifically.
final class TimecodeOutputInterlockTests: XCTestCase {

    func test_isEngaged_whenOnlyLTCIsEnabled() {
        XCTAssertTrue(TimecodeOutputInterlock.isEngaged(ltcEnabled: true, mtcEnabled: false))
    }

    // The case this epic adds: MTC alone must lock the transport to 1.0× too.
    func test_isEngaged_whenOnlyMTCIsEnabled() {
        XCTAssertTrue(TimecodeOutputInterlock.isEngaged(ltcEnabled: false, mtcEnabled: true))
    }

    func test_isEngaged_whenBothAreEnabled() {
        XCTAssertTrue(TimecodeOutputInterlock.isEngaged(ltcEnabled: true, mtcEnabled: true))
    }

    func test_isDisengaged_whenNeitherIsEnabled() {
        XCTAssertFalse(TimecodeOutputInterlock.isEngaged(ltcEnabled: false, mtcEnabled: false))
    }
}
