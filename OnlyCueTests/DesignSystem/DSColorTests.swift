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

    /// Dark-only (ADR-029): chrome tokens resolve to their dark value in
    /// every appearance — including when the host Mac is in Light mode — so
    /// the main window always matches the dark Figma design system.
    func testSurfaceResolvesDarkEvenUnderLightAppearance() throws {
        let light = try sRGBComponents(of: DS.Color.surface, appearance: .aqua)
        let dark = try sRGBComponents(of: DS.Color.surface, appearance: .darkAqua)
        XCTAssertLessThan(light[0], 0.2, "surface stays near-black under Light appearance")
        XCTAssertLessThan(dark[0], 0.2, "surface is near-black under Dark appearance")
    }

    func testTextPrimaryIsLightInkInEveryAppearance() throws {
        let light = try sRGBComponents(of: DS.Color.textPrimary, appearance: .aqua)
        let dark = try sRGBComponents(of: DS.Color.textPrimary, appearance: .darkAqua)
        XCTAssertGreaterThan(light[0], 0.85, "primary text stays light ink under Light appearance")
        XCTAssertGreaterThan(dark[0], 0.85, "primary text is light ink under Dark appearance")
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
