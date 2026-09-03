import Foundation

// Member of BOTH the app target and the CadenceWidget extension target.

/// Standalone Quick Timer feature — not connected to Event/Habit/Meal data.
/// Everything lives in App Group UserDefaults so the widget extension can
/// read/write it directly. See CADENCE_WIDGET_TIMERS.md for the full writeup
/// and removal instructions.
enum TimerSettingsStore {
    static let slotCount = 5

    private static let slotsKey = "quickTimerSlotsSeconds"
    private static let endDateKey = "quickTimerEndDate"
    private static let alarmIDKey = "quickTimerAlarmID"
    private static let notificationID = "quickTimerAlarm"

    static var notificationIdentifier: String { notificationID }

    static var defaultSlotsSeconds: [TimeInterval] { [5 * 60, 10 * 60, 15 * 60, 20 * 60, 30 * 60] }

    /// Shortest timer the countdown wheel can express, and the floor we clamp to.
    static let minimumSeconds: TimeInterval = 60

    /// "5 min" / "1 hr" / "1 hr 30 min". `compact` gives the widget-button form
    /// ("5m" / "1h30m"), where horizontal space is tight.
    static func durationLabel(_ seconds: TimeInterval, compact: Bool = false) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if compact {
            if h == 0 { return "\(m)m" }
            return m == 0 ? "\(h)h" : "\(h)h\(m)m"
        }
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    static func slotsSeconds() -> [TimeInterval] {
        guard let stored = AppGroup.defaults?.array(forKey: slotsKey) as? [Double],
              stored.count == slotCount else {
            return defaultSlotsSeconds
        }
        return stored
    }

    static func setSlotsSeconds(_ values: [TimeInterval]) {
        // The wheel can land on 0h 0m; a zero-length timer would fire instantly.
        AppGroup.defaults?.set(values.map { max($0, minimumSeconds) }, forKey: slotsKey)
    }

    // MARK: - Running state

    /// Mirror of the running timer, kept only so the *home-screen* widget can
    /// draw its own countdown. AlarmKit owns the real alarm (and the Lock Screen
    /// / Dynamic Island UI); this is a display cache, not the source of truth.
    static var endDate: Date? {
        get { AppGroup.defaults?.object(forKey: endDateKey) as? Date }
        set { AppGroup.defaults?.set(newValue, forKey: endDateKey) }
    }

    /// Id of the scheduled AlarmKit alarm, so Cancel/Stop can target it.
    static var activeAlarmID: UUID? {
        get {
            guard let raw = AppGroup.defaults?.string(forKey: alarmIDKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set { AppGroup.defaults?.set(newValue?.uuidString, forKey: alarmIDKey) }
    }

    static var isRunning: Bool {
        guard let end = endDate else { return false }
        return end > .now
    }

    static func start(seconds: TimeInterval, alarmID: UUID) {
        endDate = Date().addingTimeInterval(seconds)
        activeAlarmID = alarmID
    }

    static func cancel() {
        endDate = nil
        activeAlarmID = nil
    }
}
