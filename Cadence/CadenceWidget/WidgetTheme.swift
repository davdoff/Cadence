import SwiftUI

/// Widget-process theming. The app mirrors the selected accent into App Group
/// defaults (`WidgetSync.mirrorAccent`); surfaces derive from it via the same
/// `Color.app*` helpers the app uses. Per-habit/category colours stay `Color(hex:)`.
///
/// Light/dark: widgets follow their **own** system color scheme rather than the
/// app's manual override. Home-screen widgets can't force a scheme, and their
/// `.primary`/`.secondary` text already tracks the system — forcing only the
/// background would leave text mismatched. So the surface here is chosen from
/// the widget's `@Environment(\.colorScheme)`, keeping background and text in step.
enum WidgetTheme {
    static var accentHex: String {
        AppGroup.defaults?.string(forKey: AppGroup.accentColorKey) ?? "#E8784D"
    }

    /// Dark page surface — mirrors the app's dark app-bg mid stop (§3 1c).
    static let darkSurface = Color(hex: "#0d1524")

    /// Resolved container background for the widget's current color scheme:
    /// the accent-tinted light wash, or the dark surface.
    static func background(accentHex: String, dark: Bool) -> Color {
        dark ? darkSurface : Color.appBackground(accentHex)
    }
}
