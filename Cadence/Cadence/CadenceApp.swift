import SwiftUI
import SwiftData
import EventKit
import UserNotifications

@main
struct CadenceApp: App {
    // Shared with the notification-action handler and the Live Activity Stop
    // intent so all three mutate the same context.
    let container: ModelContainer = SharedModelContainer.shared

    // Retains the notification-center delegate for the app's lifetime (the
    // center holds it weakly). Handles the Start / Postpone / Skip buttons.
    private let notificationDelegate: NotificationDelegate

    init() {
        let delegate = NotificationDelegate(container: container)
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        NotificationService.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    NotificationService.requestAuthorization()
                    WidgetSync.mirrorAccent(
                        UserDefaults.standard.string(forKey: "accentColorHex") ?? "#E8784D"
                    )
                    await seedIfNeeded()
                    // Device calendars AND subscription feeds; never prompts.
                    await CalendarImportService.shared.syncAll(context: container.mainContext)
                    // Extends recurring series to their horizon and schedules
                    // notifications for occurrences entering the near window.
                    RecurrenceService.shared.topUp(context: container.mainContext)
                }
                // iOS posts this when the underlying calendar database changes —
                // re-sync imported events (calendar-import.md §3.4). Never prompts.
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                    CalendarImportService.shared.syncIfAuthorized(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }

    @MainActor
    private func seedIfNeeded() async {
        let context = container.mainContext
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard categoryCount == 0 else { return }

        let defaults: [(String, String)] = [
            ("Work",     "#4A90E2"),
            ("Study",    "#7B68EE"),
            ("Health",   "#5CB85C"),
            ("Meal",     "#F0AD4E"),
            ("Personal", "#9B59B6")
        ]
        for (name, hex) in defaults {
            context.insert(Category(name: name, colorHex: hex))
        }

        context.insert(UserPreferences())
        try? context.save()
    }
}
