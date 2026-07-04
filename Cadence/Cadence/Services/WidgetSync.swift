import Foundation
import WidgetKit

/// App-side bridge to the widget extension. Widgets read the shared App Group
/// SwiftData store directly, so all the app has to do is reload timelines after
/// a save — plus mirror the accent colour, since the widget process cannot see
/// the app's standard UserDefaults.
enum WidgetSync {

    /// Reload all widget timelines. Call after any save that changes events,
    /// habits, meals, or category colours.
    static func refresh() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Mirror the accent colour into App Group defaults so widgets can theme themselves.
    static func mirrorAccent(_ hex: String) {
        AppGroup.defaults?.set(hex, forKey: AppGroup.accentColorKey)
        refresh()
    }
}
