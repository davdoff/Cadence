import SwiftUI

/// Widget-process theming. The app mirrors the selected accent into App Group
/// defaults (`WidgetSync.mirrorAccent`); surfaces derive from it via the same
/// `Color.app*` helpers the app uses. Per-habit/category colours stay `Color(hex:)`.
enum WidgetTheme {
    static var accentHex: String {
        AppGroup.defaults?.string(forKey: AppGroup.accentColorKey) ?? "#E8784D"
    }
}
