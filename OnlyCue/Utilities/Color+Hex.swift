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
}
