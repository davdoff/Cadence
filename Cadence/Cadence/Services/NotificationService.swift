import Foundation
import UserNotifications

struct NotificationService {

    // MARK: - Authorization

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - General Event Notifications

    /// Schedules a reminder N minutes before the event starts. Returns the identifier.
    @discardableResult
    func scheduleEventReminder(for event: Event, reminderMinutes: Int) -> String {
        let identifier = "event-reminder-\(event.id.uuidString)"
        let fireDate = event.startTime.addingTimeInterval(TimeInterval(-reminderMinutes * 60))
        guard fireDate > Date.now else { return identifier }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = reminderMinutes == 0 ? "Starting now" : "Starting in \(reminderMinutes) min"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
        return identifier
    }

    /// Fires exactly at event start ("Starting now"). Skipped when reminderMinutes == 0,
    /// since the reminder itself already fires at start time in that case. Returns the identifier.
    @discardableResult
    func scheduleEventStartAlert(for event: Event, reminderMinutes: Int) -> String {
        let identifier = "event-start-\(event.id.uuidString)"
        guard reminderMinutes != 0, event.startTime > Date.now else { return identifier }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = "Starting now"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.startTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
        return identifier
    }

    /// Fires at event end time, prompting the user to mark it complete or missed.
    func scheduleMissedEventAlert(for event: Event) {
        let identifier = "event-missed-\(event.id.uuidString)"
        guard event.endTime > Date.now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Did you complete \"\(event.title)\"?"
        content.body = "Mark it complete or missed."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.endTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    /// Fires `days` days after event end time, nudging the user to reschedule a missed event.
    func scheduleReschedulingNudge(for event: Event, after days: Int) {
        let identifier = "event-reschedule-\(event.id.uuidString)"
        guard let fireDate = Calendar.current.date(byAdding: .day, value: days, to: event.endTime),
              fireDate > Date.now else { return }

        let content = UNMutableNotificationContent()
        content.title = "\"\(event.title)\" still needs rescheduling"
        content.body = days == 1
            ? "You missed this yesterday. Want to reschedule?"
            : "Missed \(days) days ago — want to reschedule?"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    /// Cancels the reminder, start alert, missed-alert, and reschedule nudge for an event.
    func cancelEventNotifications(for event: Event) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "event-reminder-\(event.id.uuidString)",
            "event-start-\(event.id.uuidString)",
            "event-missed-\(event.id.uuidString)",
            "event-reschedule-\(event.id.uuidString)"
        ])
    }

    /// Returns true if notifications should fire for this event given current prefs.
    func isNotificationEnabled(for event: Event, prefs: UserPreferences) -> Bool {
        guard prefs.notificationsEnabled else { return false }
        guard let catID = event.category?.id else { return true }
        return prefs.perCategoryNotifications()[catID] ?? true
    }

    // MARK: - Meal Notifications

    @discardableResult
    func scheduleMealNotification(for event: Event, reminderMinutes: Int) -> String {
        let identifier = "meal-\(event.id.uuidString)"
        let fireDate = event.startTime.addingTimeInterval(TimeInterval(-reminderMinutes * 60))
        guard fireDate > Date.now else { return identifier }

        let content = UNMutableNotificationContent()
        if event.title == "Breakfast" {
            content.title = "Breakfast soon"
            content.body = "Breakfast in \(reminderMinutes) min — don't skip it!"
        } else {
            content.title = "Time to cook"
            content.body = "Time to cook: \(event.title)"
        }
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
        return identifier
    }

    // MARK: - Breakfast Missed Streak

    func scheduleBreakfastMissedNudge(breakfastHour: Int, breakfastMinute: Int) {
        let identifier = "breakfast-missed-streak"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Missed breakfast"
        content.body = "You've missed breakfast 3 days. Adjust the time?"
        content.sound = .default

        var comps = DateComponents()
        comps.hour = breakfastHour
        comps.minute = breakfastMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    // MARK: - Cancellation

    func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelBreakfastMissedNudge() {
        cancel(identifier: "breakfast-missed-streak")
    }
}
