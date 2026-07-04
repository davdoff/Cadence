import Foundation

// Member of BOTH the app target and the CadenceWidget extension target.

/// Shared App Group constants — the SwiftData store location and the
/// UserDefaults suite used to mirror the accent colour into the widget process.
enum AppGroup {
    static let id = "group.com.david.Cadence"
    static let accentColorKey = "accentColorHex"

    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }

    static var storeURL: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: id)!
            .appendingPathComponent("Cadence.store")
    }
}
