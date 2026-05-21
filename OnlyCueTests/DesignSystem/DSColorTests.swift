import XCTest
import SwiftUI
import AppKit
@testable import OnlyCue

final class DSColorTests: XCTestCase {

    /// Resolves a token's sRGB components under a specific appearance.
    private func sRGBComponents(of color: Color,
                                appearance name: NSAppearance.Name) throws -> [CGFloat] {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        let rgb = try XCTUnwrap(resolved)
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    }

    func testSurfaceResolvesLighterInLightThanDark() throws {
        let light = try sRGBComponents(of: DS.Color.surface, appearance: .aqua)
        let dark = try sRGBComponents(of: DS.Color.surface, appearance: .darkAqua)
        XCTAssertGreaterThan(light[0], 0.9, "light surface should be near-white")
        XCTAssertLessThan(dark[0], 0.2, "dark surface should be near-black")
    }

    func testTextPrimaryInvertsBetweenAppearances() throws {
        let light = try sRGBComponents(of: DS.Color.textPrimary, appearance: .aqua)
        let dark = try sRGBComponents(of: DS.Color.textPrimary, appearance: .darkAqua)
        XCTAssertLessThan(light[0], 0.25, "light-mode text is dark ink")
        XCTAssertGreaterThan(dark[0], 0.85, "dark-mode text is light ink")
    }

    func testNeutralsAreWarmTinted() throws {
        // Warm tint: red component >= blue component on every neutral.
        for color in [DS.Color.surface, DS.Color.panel, DS.Color.border, DS.Color.textSecondary] {
            let rgb = try sRGBComponents(of: color, appearance: .aqua)
            XCTAssertGreaterThanOrEqual(rgb[0], rgb[2], "neutral should be warm (red >= blue)")
        }
    }

    func testInkOnContrastsWithInk() throws {
        let ink = try sRGBComponents(of: DS.Color.ink, appearance: .aqua)
        let inkOn = try sRGBComponents(of: DS.Color.inkOn, appearance: .aqua)
        XCTAssertGreaterThan(abs(ink[0] - inkOn[0]), 0.6, "ink and inkOn must contrast")
    }
}
