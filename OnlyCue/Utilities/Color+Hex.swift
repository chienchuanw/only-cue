import AppKit
import SwiftUI

extension Color {

    init?(hex: String) {
        var trimmed = hex
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&value), trimmed.allSatisfy(\.isHexDigit) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    /// Returns the canonical `#RRGGBB` form (uppercase) by converting through the sRGB
    /// color space. Components are clamped to `0...1` before scaling so wide-gamut colors
    /// (e.g., P3 values that fall outside sRGB) round to a valid hex byte.
    /// Returns nil only when the color has no representable RGB components.
    func toHex() -> String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((min(max(srgb.redComponent, 0), 1) * 255).rounded())
        let green = Int((min(max(srgb.greenComponent, 0), 1) * 255).rounded())
        let blue = Int((min(max(srgb.blueComponent, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
