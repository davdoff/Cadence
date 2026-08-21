import AppIntents
import WidgetKit
import UserNotifications

// Standalone Quick Timer feature — see CADENCE_WIDGET_TIMERS.md.
// Not wired to Event/Habit/Meal data; safe to delete independently.

struct StartQuickTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts a Quick Timer countdown.")

    /// Widget-button only: a raw seconds parameter is meaningless in Shortcuts.
    static let isDiscoverable = false

    @Parameter(title: "Seconds")
    var seconds: TimeInterval

    init() {}

    init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        TimerSettingsStore.start(seconds: seconds)
        await scheduleAlarmNotification(in: seconds)
        WidgetCenter.shared.reloadTimelines(ofKind: "QuickTimer")
        return .result()
    }

    private func scheduleAlarmNotification(in seconds: TimeInterval) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [TimerSettingsStore.notificationIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = TimerSettingsStore.durationLabel(seconds) + " is up."
        content.sound = .default
        // NOTE: `.timeSensitive` would need the
        // com.apple.developer.usernotifications.time-sensitive entitlement,
        // which this app doesn't have — iOS would silently downgrade it.

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: TimerSettingsStore.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}

struct CancelQuickTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Cancel Timer"
    static let description = IntentDescription("Cancels the running Quick Timer.")

    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        TimerSettingsStore.cancel()
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [TimerSettingsStore.notificationIdentifier])
        WidgetCenter.shared.reloadTimelines(ofKind: "QuickTimer")
        return .result()
    }
}
