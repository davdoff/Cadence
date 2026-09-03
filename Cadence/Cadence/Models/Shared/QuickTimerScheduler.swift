import Foundation
import SwiftUI
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
#endif

// Member of BOTH the app target and the CadenceWidget extension target.
// Standalone Quick Timer feature — see CADENCE_WIDGET_TIMERS.md.
//
// Uses only APIs available to both targets (Foundation, SwiftUI, AlarmKit,
// UserNotifications) — no app-only services — so it compiles identically in
// each, the same convention StopEventIntent.swift follows.

/// How a Quick Timer gets scheduled. Two implementations: a real AlarmKit alarm
/// on iOS 26+, and a plain local notification below that. Isolating it behind a
/// protocol keeps the version branch to a single call site (`QuickTimer`).
protocol QuickTimerScheduling {
    func start(seconds: TimeInterval, id: UUID) async throws
    func cancel(id: UUID)
    func requestAuthorization() async
}

// MARK: - AlarmKit (iOS 26+) — a real alarm

#if canImport(AlarmKit)

/// AlarmKit requires a metadata type, but we have nothing extra to show in the
/// alarm UI, so it is deliberately empty.
@available(iOS 26.0, *)
struct QuickTimerMetadata: AlarmMetadata {
    init() {}
}

/// Schedules a genuine system alarm: it breaks through Silent Mode and Focus,
/// takes over the Lock Screen, and must be dismissed.
@available(iOS 26.0, *)
struct AlarmKitTimerScheduler: QuickTimerScheduling {

    func start(seconds: TimeInterval, id: UUID) async throws {
        // Minimal presentation: a countdown with no pause, and an alert whose
        // Stop button the system supplies for us (the `stopButton:` initialiser
        // is deprecated precisely because of that).
        let presentation = AlarmPresentation(
            alert: .init(title: "Timer done", secondaryButton: nil, secondaryButtonBehavior: nil),
            countdown: .init(title: "Quick Timer", pauseButton: nil),
            paused: nil
        )

        // Read the accent straight from App Group defaults rather than via
        // WidgetTheme — that type lives in CadenceWidget/ and so isn't visible
        // to the app target, which also compiles this file.
        let accentHex = AppGroup.defaults?.string(forKey: AppGroup.accentColorKey) ?? "#E8784D"

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: QuickTimerMetadata(),
            tintColor: Color(hex: accentHex)
        )

        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: seconds,
            attributes: attributes,
            // Pressing the system Stop button runs this, which clears our
            // display mirror so the home-screen widget returns to its presets.
            stopIntent: QuickTimerStoppedIntent(),
            secondaryIntent: nil,
            sound: .default
        )

        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    func cancel(id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
    }

    func requestAuthorization() async {
        // Needs NSAlarmKitUsageDescription in the *app's* Info.plist — without
        // it no prompt appears and scheduling silently fails.
        _ = try? await AlarmManager.shared.requestAuthorization()
    }
}

#endif

// MARK: - Fallback (below iOS 26) — an ordinary notification

/// Pre-26 devices get a normal local notification. It respects Silent Mode and
/// Focus, so it can finish without making a sound — the limitation that
/// motivated the AlarmKit path above.
struct NotificationTimerScheduler: QuickTimerScheduling {

    func start(seconds: TimeInterval, id: UUID) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [TimerSettingsStore.notificationIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = TimerSettingsStore.durationLabel(seconds) + " is up."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: TimerSettingsStore.notificationIdentifier,
            content: content,
            trigger: trigger
        ))
    }

    func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [TimerSettingsStore.notificationIdentifier])
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

// MARK: - Facade

/// The only place the iOS-version branch lives.
enum QuickTimer {

    /// True when this device can ring a real alarm rather than a notification.
    static var usesRealAlarm: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    private static var scheduler: QuickTimerScheduling {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmKitTimerScheduler() }
        #endif
        return NotificationTimerScheduler()
    }

    static func requestAuthorization() async {
        await scheduler.requestAuthorization()
    }

    /// Schedules the alarm, then mirrors it locally for the home-screen widget.
    /// The mirror is only written on success, so a rejected authorization can't
    /// leave the widget counting down to an alarm that will never ring.
    static func start(seconds: TimeInterval) async {
        let id = UUID()
        do {
            try await scheduler.start(seconds: seconds, id: id)
            TimerSettingsStore.start(seconds: seconds, alarmID: id)
        } catch {
            TimerSettingsStore.cancel()
        }
    }

    static func cancel() {
        if let id = TimerSettingsStore.activeAlarmID {
            scheduler.cancel(id: id)
        }
        TimerSettingsStore.cancel()
    }
}
