import XCTest
import SwiftUI
@testable import OnlyCue

final class WaveformViewColorTests: XCTestCase {

    /// ADR-024 / Figma 318:1228: the waveform body is achromatic chrome, not
    /// data, so it fills with a `DS.Color` neutral — never the cue/indigo
    /// accent (which is reserved for primary actions and cue-type color).
    func test_defaultFill_isAchromaticNeutral_notAccent() {
        let view = WaveformView(buckets: [])
        XCTAssertEqual(view.color, DS.Color.textSecondary)
        XCTAssertNotEqual(view.color, DS.Color.cueIndigo)
        XCTAssertNotEqual(view.color, .accentColor)
    }
}
