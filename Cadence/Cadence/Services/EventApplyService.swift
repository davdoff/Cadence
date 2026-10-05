import Foundation
import SwiftData

/// Writes confirmed plans into SwiftData: inserting new events, moving existing
/// ones, and the device-side side effects every such write needs (notifications,
/// widget refresh). Shared by the Ask AI confirm cards and day templates so both
/// paths insert and move events identically.
enum EventApplyService {

    /// Inserts one event per draft, matching each draft's category by
    /// case-insensitive name (nil when nothing matches), and schedules its
    /// notifications. Does not save — call `finalize` once after the batch.
    @MainActor
    @discardableResult
    static func insert(
        _ drafts: [EventDraft],
        source: EventSource,
        fallbackTitle: String = "",
        prefs: UserPreferences,
        categories: [Category],
        context: ModelContext
    ) -> [Event] {
        let svc = NotificationService()
        return drafts.map { draft in
            let matched = categories.first { $0.name.lowercased() == draft.categoryName.lowercased() }
            let event = Event(
                title: draft.title.isEmpty ? fallbackTitle : draft.title,
                startTime: draft.start,
                endTime: draft.end,
                category: matched,
                source: source
            )
            context.insert(event)
            scheduleNotifications(for: event, prefs: prefs, svc: svc)
            return event
        }
    }

    /// Moves an event to a new time: cancels and reschedules its notifications
    /// and resets it to pending. An imported event is flagged as locally edited
    /// so the next calendar sync keeps the new time instead of reverting it
    /// (same as a manual edit in AddEventView). Only this occurrence moves for
    /// a recurring event. Does not save.
    @MainActor
    static func move(_ event: Event, to start: Date, end: Date, prefs: UserPreferences) {
        let svc = NotificationService()
        svc.cancelEventNotifications(for: event)
        event.startTime = start
        event.endTime = end
        event.status = .pending
        if event.source == .imported { event.locallyEditedTime = true }
        scheduleNotifications(for: event, prefs: prefs, svc: svc)
    }

    /// Finds an existing category by case-insensitive name, or creates one when
    /// the name is new — so a request never fails just because the category
    /// doesn't exist yet (David: never refuse an event task).
    @MainActor
    static func resolveOrCreateCategory(named name: String, in categories: [Category], context: ModelContext) -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = categories.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let palette = AddCategoryView.palette
        let colorHex = palette[abs(trimmed.hashValue) % palette.count]
        let created = Category(name: trimmed, colorHex: colorHex)
        context.insert(created)
        return created
    }

    @MainActor
    static func scheduleNotifications(for event: Event, prefs: UserPreferences, svc: NotificationService = NotificationService()) {
        guard svc.isNotificationEnabled(for: event, prefs: prefs) else { return }
        event.notificationIdentifier = svc.scheduleEventReminder(
            for: event, reminderMinutes: prefs.defaultReminderMinutes
        )
        svc.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
        svc.scheduleMissedEventAlert(for: event)
    }

    /// One save and one widget refresh for the whole batch.
    @MainActor
    static func finalize(context: ModelContext) {
        try? context.save()
        WidgetSync.refresh()
    }
}
