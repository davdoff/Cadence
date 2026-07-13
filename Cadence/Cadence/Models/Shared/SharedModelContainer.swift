import Foundation
import SwiftData

// Member of BOTH the app target and the CadenceWidget extension target.

/// Builds the SwiftData container on the shared App Group store so the app
/// and the widget extension read and write the same data.
enum SharedModelContainer {

    static let schema = Schema([
        Event.self,
        EventSeries.self,
        Category.self,
        Meal.self,
        UserPreferences.self,
        Habit.self,
        CalendarImportSource.self
    ])

    /// The one container instance for the app process. Shared so the UI's
    /// `@Query`, the notification-action handler, and the Live Activity Stop
    /// intent all read and write the *same* context and see each other's
    /// changes live. App-process only (runs the legacy migration first); the
    /// widget reads the store through `WidgetDataStore`, not this.
    static let shared: ModelContainer = {
        migrateLegacyStoreIfNeeded()
        return make()
    }()

    /// Opens the App Group store. On a schema mismatch the store files are
    /// wiped and recreated fresh — same recovery behaviour the app has always had.
    static func make() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, url: AppGroup.storeURL)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            for suffix in ["", "-wal", "-shm"] {
                let file = URL(fileURLWithPath: AppGroup.storeURL.path + suffix)
                try? FileManager.default.removeItem(at: file)
            }
            return try! ModelContainer(for: schema, configurations: config)
        }
    }

    /// One-time migration of the legacy store (Application Support/default.store)
    /// into the App Group container. Call from the app process only — the widget
    /// sandbox cannot see the app's Application Support directory. No-op once the
    /// group store exists or when there is no legacy store.
    static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: AppGroup.storeURL.path),
              let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        let legacyStore = appSupport.appendingPathComponent("default.store")
        guard fm.fileExists(atPath: legacyStore.path) else { return }

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacyStore.path + suffix)
            let destination = URL(fileURLWithPath: AppGroup.storeURL.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.copyItem(at: source, to: destination)
        }
    }
}
