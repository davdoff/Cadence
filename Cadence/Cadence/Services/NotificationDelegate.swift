import Foundation
import SwiftData
import UserNotifications

/// Handles taps on the Start / Postpone 15m / Skip notification buttons and
/// shows banners while the app is foreground. Registered as the notification
/// centre's delegate at launch. Holds the shared SwiftData container so it can
/// apply an action even when the tap cold-launched the app.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
    }

    /// Without this, iOS suppresses notifications while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            handle(action: action, userInfo: userInfo)
            completionHandler()
        }
    }

    @MainActor
    private func handle(action: String, userInfo: [AnyHashable: Any]) {
        guard let idString = userInfo["eventID"] as? String,
              let uuid = UUID(uuidString: idString) else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == uuid })
        guard let event = try? context.fetch(descriptor).first else { return }

        let svc = NotificationService()
        switch action {
        case NotificationService.Action.start:
            // Same as tapping Start in Today: stamp the timer, schedule the
            // "done" alert. Auto-complete reconciliation finishes it later.
            event.startedAt = .now
            svc.scheduleEventCompletionAlert(for: event)

        case NotificationService.Action.postpone:
            // Snooze: slide the event 15 min later and rebuild its notifications.
            svc.cancelEventNotifications(for: event)
            let offset: TimeInterval = 15 * 60
            event.startTime = event.startTime.addingTimeInterval(offset)
            event.endTime   = event.endTime.addingTimeInterval(offset)
            let lead = reminderLead(context: context)
            event.notificationIdentifier = svc.scheduleEventReminder(for: event, reminderMinutes: lead)
            svc.scheduleEventStartAlert(for: event, reminderMinutes: lead)
            svc.scheduleMissedEventAlert(for: event)

        case NotificationService.Action.skip:
            // Same as swipe-to-missed in Today.
            event.status = .missed
            svc.cancelEventNotifications(for: event)
            svc.scheduleReschedulingNudge(for: event, after: 2)

        default:
            // Default tap / dismiss — just opens the app, nothing to change.
            return
        }

        try? context.save()
        WidgetSync.refresh()
    }

    @MainActor
    private func reminderLead(context: ModelContext) -> Int {
        let prefs = (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first
        return prefs?.defaultReminderMinutes ?? 15
    }
}
