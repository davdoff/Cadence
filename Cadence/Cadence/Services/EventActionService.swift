import Foundation
import SwiftData

/// The single place that applies a lifecycle action to an event — start,
/// complete, or skip. Shared by the Today view, the notification action
/// buttons, and the Live Activity Stop button so all three stay in lockstep.
///
/// This is the OS-blind decision logic (status transitions, habit streaks);
/// the device-side side effects it drives — local notifications, the Live
/// Activity, and the widget refresh — are the parts a future Android client
/// would swap out.
enum EventActionService {

    /// Begins the event: stamps the timer, schedules the completion alert, and
    /// raises the Live Activity countdown.
    @MainActor
    static func start(_ event: Event, context: ModelContext) {
        event.startedAt = .now
        NotificationService().scheduleEventCompletionAlert(for: event)
        try? context.save()
        LiveActivityService.start(for: event)
        WidgetSync.refresh()
    }

    /// Marks the event complete, incrementing any habit correlated with its
    /// category, and tears down the Live Activity.
    @MainActor
    static func complete(_ event: Event, context: ModelContext) {
        event.status = .completed
        NotificationService().cancelEventNotifications(for: event)
        if let cat = event.category?.name {
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            for habit in habits where habit.correlatedCategoryName?.lowercased() == cat.lowercased() {
                habit.increment()
            }
        }
        try? context.save()
        LiveActivityService.end(eventID: event.id)
        WidgetSync.refresh()
    }

    /// Marks the event missed, schedules the reschedule nudge, and tears down
    /// the Live Activity.
    @MainActor
    static func miss(_ event: Event, context: ModelContext) {
        let svc = NotificationService()
        event.status = .missed
        svc.cancelEventNotifications(for: event)
        svc.scheduleReschedulingNudge(for: event, after: 2)
        try? context.save()
        LiveActivityService.end(eventID: event.id)
        WidgetSync.refresh()
    }
}
