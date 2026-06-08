import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r, g, b: UInt64
        switch hex.count {
        case 3:  (r, g, b) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6:  (r, g, b) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    static let cadenceOrange      = Color(hex: "#E8784D")
    static let cadenceOrangeDark  = Color(hex: "#C45E32")
    static let cadenceOrangeLight = Color(hex: "#F2A07A")
    static let cadenceCream       = Color(hex: "#FFF8F2")
    static let cadenceCreamDeep   = Color(hex: "#F0E6D8")
}
