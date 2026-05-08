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
    /// color space. Returns nil only when the color has no representable RGB components
    /// (which shouldn't happen for any color produced by this app).
    func toHex() -> String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
