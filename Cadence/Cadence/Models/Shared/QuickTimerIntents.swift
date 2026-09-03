import AppIntents
import WidgetKit

// Member of BOTH the app target and the CadenceWidget extension target.
// Standalone Quick Timer feature — see CADENCE_WIDGET_TIMERS.md.
//
// These are `LiveActivityIntent`, not plain `AppIntent`, so `perform()` runs in
// the *app* process — the same trick StopEventIntent.swift uses. That matters:
// AlarmKit's authorization and its NSAlarmKitUsageDescription belong to the app,
// so scheduling from the widget extension process is unreliable. The widget
// still references these types to build its buttons, hence both memberships.

struct StartQuickTimerIntent: LiveActivityIntent {
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
        await QuickTimer.start(seconds: seconds)
        WidgetCenter.shared.reloadTimelines(ofKind: "QuickTimer")
        return .result()
    }
}

struct CancelQuickTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Timer"
    static let description = IntentDescription("Cancels the running Quick Timer.")

    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        QuickTimer.cancel()
        WidgetCenter.shared.reloadTimelines(ofKind: "QuickTimer")
        return .result()
    }
}

/// Handed to AlarmKit as the alarm's `stopIntent`. It only clears our local
/// display mirror — it must NOT call `QuickTimer.cancel()`, because the alarm
/// has already stopped by the time this runs and cancelling it again would be
/// redundant work against a dead id.
struct QuickTimerStoppedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer"
    static let description = IntentDescription("Clears the Quick Timer once its alarm stops.")

    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        TimerSettingsStore.cancel()
        WidgetCenter.shared.reloadTimelines(ofKind: "QuickTimer")
        return .result()
    }
}
