import SwiftUI

extension Color {
    init(hex: String) {
        let (r, g, b) = Color.rgbComponents(hex: hex)
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// Parses a 3- or 6-digit hex string into 0–255 RGB components.
    private static func rgbComponents(hex rawHex: String) -> (UInt64, UInt64, UInt64) {
        let hex = rawHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        switch hex.count {
        case 3:  return ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6:  return (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        default: return (0, 0, 0)
        }
    }

    /// Blends `accentHex` into white by `amount` (0 = white, 1 = full accent).
    private static func tintedWhite(_ accentHex: String, amount: Double) -> Color {
        let (r, g, b) = rgbComponents(hex: accentHex)
        let mix: (UInt64) -> Double = { 255 - (255 - Double($0)) * amount }
        return Color(.sRGB, red: mix(r) / 255, green: mix(g) / 255, blue: mix(b) / 255)
    }

    /// Very light tint of `accentHex` — themed replacement for the fixed cream page background.
    static func appBackground(_ accentHex: String) -> Color { tintedWhite(accentHex, amount: 0.07) }

    /// Slightly deeper tint of `accentHex` — themed replacement for cadenceCreamDeep (dividers/borders).
    static func appDeep(_ accentHex: String) -> Color { tintedWhite(accentHex, amount: 0.16) }

    /// The selected accent itself — themed replacement for the fixed `cadenceOrange`.
    static func appAccent(_ accentHex: String) -> Color { Color(hex: accentHex) }

    /// Lighter accent — themed replacement for `cadenceOrangeLight` (gradient tops, soft fills).
    static func accentLight(_ accentHex: String) -> Color { tintedWhite(accentHex, amount: 0.55) }

    /// Darker accent — themed replacement for `cadenceOrangeDark` (gradient bottoms).
    static func accentDark(_ accentHex: String) -> Color { darkened(accentHex, amount: 0.78) }

    /// Multiplies each RGB component of `accentHex` by `amount` (0 = black, 1 = unchanged).
    private static func darkened(_ accentHex: String, amount: Double) -> Color {
        let (r, g, b) = rgbComponents(hex: accentHex)
        return Color(.sRGB, red: Double(r) * amount / 255, green: Double(g) * amount / 255, blue: Double(b) * amount / 255)
    }

    static let cadenceOrange      = Color(hex: "#E8784D")
    static let cadenceOrangeDark  = Color(hex: "#C45E32")
    static let cadenceOrangeLight = Color(hex: "#F2A07A")
    static let cadenceCream       = Color(hex: "#FFF8F2")
    static let cadenceCreamDeep   = Color(hex: "#F0E6D8")
}
