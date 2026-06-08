import Foundation
import UserNotifications

struct NotificationService {

    // MARK: - Meal Notifications

    /// Schedules a local notification N minutes before the meal event starts.
    /// Returns the notification identifier so it can be stored on the Event for later cancellation.
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
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        return identifier
    }

    // MARK: - Breakfast Missed Streak

    /// Schedules (or replaces) the "missed 3 days" nudge to fire at breakfast time on the next day.
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
        // repeats: false fires once at the next matching wall-clock time
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cancellation

    func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelBreakfastMissedNudge() {
        cancel(identifier: "breakfast-missed-streak")
    }
}
