import XCTest
@testable import OnlyCue

/// `SMPTEFramerate.shortDisplayName` — the compact framerate caption used at the
/// top-right of the playhead clock (#463, Figma `318:1228`/`318:1369` show a
/// lowercase `30 fps`). The verbose `displayName` ("30 fps (non-drop)") is kept
/// for the Settings picker.
final class SMPTEFramerateTests: XCTestCase {

    func test_shortDisplayName_dropsTheNonDropQualifier() {
        XCTAssertEqual(SMPTEFramerate.fps24.shortDisplayName, "24 fps")
        XCTAssertEqual(SMPTEFramerate.fps25.shortDisplayName, "25 fps")
        XCTAssertEqual(SMPTEFramerate.fps30.shortDisplayName, "30 fps")
    }

    func test_shortDisplayName_dropFrame_isMarkedDF() {
        XCTAssertEqual(SMPTEFramerate.fps30drop.shortDisplayName, "30 fps DF")
    }
}
