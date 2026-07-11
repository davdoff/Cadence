import AppIntents
import SwiftData
import ActivityKit
import WidgetKit
import UserNotifications

// Member of BOTH targets: the widget references it to build the Stop button,
// but as a `LiveActivityIntent` its `perform()` runs in the *app* process.
//
// It deliberately uses only APIs available to both targets (SwiftData models,
// ActivityKit, WidgetKit, UserNotifications) — no app-only services — so it
// compiles identically in each and needs no compilation flag. The completion
// logic here mirrors `EventActionService.complete`; keep them in sync.

/// Stop button on the running-event Live Activity: finishes the event, marks it
/// complete (incrementing any correlated habit), and tears the activity down.
struct StopEventIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop event"
    static let description = IntentDescription("Finish the running event and mark it complete.")

    @Parameter(title: "Event ID")
    var eventID: String

    init() {}
    init(eventID: String) { self.eventID = eventID }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            guard let uuid = UUID(uuidString: eventID) else { return }
            let context = SharedModelContainer.shared.mainContext
            let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == uuid })
            guard let event = try? context.fetch(descriptor).first else { return }

            event.status = .completed
            if let cat = event.category?.name {
                let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
                for habit in habits where habit.correlatedCategoryName?.lowercased() == cat.lowercased() {
                    habit.increment()
                }
            }
            try? context.save()

            // Same identifiers NotificationService uses (app-only type, so
            // replicated here to stay flag-free).
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
                "event-reminder-\(uuid.uuidString)",
                "event-start-\(uuid.uuidString)",
                "event-missed-\(uuid.uuidString)",
                "event-finished-\(uuid.uuidString)",
                "event-reschedule-\(uuid.uuidString)"
            ])
        }

        // Tear down the Live Activity and refresh the home-screen widgets.
        for activity in Activity<EventActivityAttributes>.activities
        where activity.attributes.eventID == eventID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}
