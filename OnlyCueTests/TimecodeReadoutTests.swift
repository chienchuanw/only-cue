import XCTest
@testable import OnlyCue

final class TimecodeReadoutTests: XCTestCase {

    // The bug this feature exists to fix: the readout used to be gated on the
    // LTC *output* master switch, so a designer who only wanted to *read* the
    // timecode on a file had to enable LTC *generation* to see it (#712).
    func test_isVisible_whenTheFileCarriesTimecode_evenWithLTCOutputOff() {
        XCTAssertTrue(TimecodeReadout.isVisible(hasFileTimecode: true, ltcOutputEnabled: false))
    }

    // Unchanged for anyone already using LTC output: enabling it still shows the
    // readout, file timecode or not.
    func test_isVisible_whenLTCOutputIsOn() {
        XCTAssertTrue(TimecodeReadout.isVisible(hasFileTimecode: false, ltcOutputEnabled: true))
    }

    // Neither → nothing to say. Keeps the transport bar clear for projects that
    // don't work in timecode at all, which is how it behaves today.
    func test_isHidden_whenThereIsNeither() {
        XCTAssertFalse(TimecodeReadout.isVisible(hasFileTimecode: false, ltcOutputEnabled: false))
    }

    // The source has to be legible at a glance: a designer must be able to tell
    // the file's own timecode from the one OnlyCue computed.
    func test_prefix_namesTheSource() {
        XCTAssertEqual(TimecodeReadout.prefix(hasFileTimecode: true), "FILE")
        XCTAssertEqual(TimecodeReadout.prefix(hasFileTimecode: false), "SMPTE")
    }
}
