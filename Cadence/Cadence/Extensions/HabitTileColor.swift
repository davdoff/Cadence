import SwiftUI

/// A per-habit color identity (CADENCE_DESIGN_SYSTEM §3 "Habit tile colors" +
/// §5). User-assignable at habit creation, and **extensible** — add entries to
/// `all` and the picker/cards pick them up automatically. Each identity carries
/// a light and a dark token set so tiles read correctly in both surfaces.
///
/// Stored on `Habit.tileColorID` as a plain `String`, which keeps the
/// widget-shared model Foundation-only; resolve to live tokens with
/// `HabitTileColor.by(id:).tokens(dark:)`.
struct HabitTileColor: Identifiable {
    let id: String
    let name: String
    /// Widget-facing flat hex (mirrored into `Habit.colorHex`) so widgets, which
    /// read the flat color, stay visually in sync until Phase 6.
    let solidHex: String
    let lightTokens: Tokens
    let darkTokens: Tokens

    func tokens(dark: Bool) -> Tokens { dark ? darkTokens : lightTokens }

    struct Tokens {
        /// 2-stop tile background (drawn top → bottom).
        let tileBg: [Color]
        /// Icon tint sitting on the tile.
        let icon: Color
        /// 2-stop button / progress gradient (135°: bottomLeading → topTrailing).
        let button: [Color]

        /// Build from hex strings (+ optional per-stop alpha on the tile bg).
        /// Keeps each color a small, fast-to-type-check expression, avoiding the
        /// Swift type-checker timeouts big nested `Color` literals can trigger.
        init(bg: [String], bgAlpha: [Double] = [1, 1], icon: String, button: [String]) {
            self.tileBg = zip(bg, bgAlpha).map { Color(hex: $0.0).opacity($0.1) }
            self.icon   = Color(hex: icon)
            self.button = button.map { Color(hex: $0) }
        }

        var tileGradient: LinearGradient {
            LinearGradient(colors: tileBg, startPoint: .top, endPoint: .bottom)
        }
        var buttonGradient: LinearGradient {
            LinearGradient(colors: button, startPoint: .bottomLeading, endPoint: .topTrailing)
        }
        /// Flat representative color (the button's deep end): for solid progress
        /// fills, the widget mirror, and anywhere a single color is needed.
        var solid: Color { button.last ?? icon }
    }
}

// MARK: - Catalog

extension HabitTileColor {
    /// The picker palette (order shown in the creation grid). Extends the §3
    /// starter set (orange / pink / slate) with a full warm→cool→neutral range;
    /// append freely to grow it further.
    static let all: [HabitTileColor] = [
        orange, pink, red, amber, green, teal, blue, indigo, purple, slate
    ]

    /// Fallback identity used for existing habits migrated in and any unknown id.
    static let defaultID = "orange"

    static func by(id: String) -> HabitTileColor {
        all.first { $0.id == id } ?? orange
    }

    static let orange = HabitTileColor(
        id: "orange", name: "Orange", solidHex: "#e07d13",
        lightTokens: .init(bg: ["#ffdca6", "#ffbf6b"], icon: "#e07d13", button: ["#ff9d33", "#e07514"]),
        darkTokens:  .init(bg: ["#ffaf50", "#e8862a"], bgAlpha: [0.28, 0.14], icon: "#ffb865", button: ["#ffaa4d", "#e8862a"]))

    static let pink = HabitTileColor(
        id: "pink", name: "Pink", solidHex: "#e5237a",
        lightTokens: .init(bg: ["#ffc4dd", "#ff8fbb"], icon: "#e5237a", button: ["#ff5c9d", "#e01271"]),
        darkTokens:  .init(bg: ["#ff5aa0", "#ff3c82"], bgAlpha: [0.28, 0.14], icon: "#ff86b8", button: ["#ff6aa6", "#e83d80"]))

    static let slate = HabitTileColor(
        id: "slate", name: "Slate", solidHex: "#33506e",
        lightTokens: .init(bg: ["#d6e0ec", "#b0c1d4"], icon: "#33506e", button: ["#4d6b8c", "#2c4763"]),
        darkTokens:  .init(bg: ["#8caacd", "#5a789b"], bgAlpha: [0.26, 0.12], icon: "#a9c2dc", button: ["#7594b4", "#4f6d8c"]))

    static let red = HabitTileColor(
        id: "red", name: "Red", solidHex: "#d63a33",
        lightTokens: .init(bg: ["#ffcac6", "#ff9d97"], icon: "#d63a33", button: ["#ff6f68", "#e0443d"]),
        darkTokens:  .init(bg: ["#ff7a73", "#e0443d"], bgAlpha: [0.28, 0.14], icon: "#ff938c", button: ["#ff6f68", "#e0443d"]))

    static let amber = HabitTileColor(
        id: "amber", name: "Amber", solidHex: "#c98a0e",
        lightTokens: .init(bg: ["#ffeaa8", "#ffd766"], icon: "#c98a0e", button: ["#ffcf47", "#e0a815"]),
        darkTokens:  .init(bg: ["#ffd766", "#e0a815"], bgAlpha: [0.28, 0.14], icon: "#ffdd7a", button: ["#ffcf47", "#e0a815"]))

    static let green = HabitTileColor(
        id: "green", name: "Green", solidHex: "#12a35f",
        lightTokens: .init(bg: ["#b7f0cf", "#84e6ac"], icon: "#12a35f", button: ["#3ee08f", "#0fb466"]),
        darkTokens:  .init(bg: ["#4ff0a0", "#17c47a"], bgAlpha: [0.26, 0.12], icon: "#5fe6a5", button: ["#4ff0a0", "#17c47a"]))

    static let teal = HabitTileColor(
        id: "teal", name: "Teal", solidHex: "#0f9d8c",
        lightTokens: .init(bg: ["#a8f0e6", "#78e6d6"], icon: "#0f9d8c", button: ["#2fd8c2", "#12ab98"]),
        darkTokens:  .init(bg: ["#3fe0cd", "#12b5a0"], bgAlpha: [0.26, 0.12], icon: "#5fe6d5", button: ["#3fd8c4", "#12ab98"]))

    static let blue = HabitTileColor(
        id: "blue", name: "Blue", solidHex: "#1f6fe8",
        lightTokens: .init(bg: ["#bcd8ff", "#8fbcff"], icon: "#1f6fe8", button: ["#4aa8ff", "#1f6fe8"]),
        darkTokens:  .init(bg: ["#5cb3ff", "#2b82f5"], bgAlpha: [0.26, 0.12], icon: "#79b6ff", button: ["#5cb3ff", "#2b82f5"]))

    static let indigo = HabitTileColor(
        id: "indigo", name: "Indigo", solidHex: "#5a52e0",
        lightTokens: .init(bg: ["#cfccff", "#a9a3ff"], icon: "#5a52e0", button: ["#8a84f5", "#5a52e0"]),
        darkTokens:  .init(bg: ["#a892ff", "#6a58f0"], bgAlpha: [0.26, 0.12], icon: "#b0a8ff", button: ["#8a84f5", "#5a52e0"]))

    static let purple = HabitTileColor(
        id: "purple", name: "Purple", solidHex: "#8a3ff0",
        lightTokens: .init(bg: ["#e0c6ff", "#c79bff"], icon: "#8a3ff0", button: ["#c07bff", "#8a3ff0"]),
        darkTokens:  .init(bg: ["#cd8bff", "#9a54f5"], bgAlpha: [0.26, 0.12], icon: "#c99bff", button: ["#cd8bff", "#9a54f5"]))
}
