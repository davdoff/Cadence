import Foundation

enum EventStatus: String, Codable {
    // Shared with the widget target — append new cases only, never reorder.
    // .displaced = "the planner moved this aside, needs rescheduling" — NOT a
    // failure; excluded from missed/completion stats (ai-planner.md §6).
    case pending, completed, missed, displaced
}

enum HabitType: String, Codable {
    case good, bad
}

/// Manual light/dark override (CADENCE_README §5b). Lives in the shared
/// model layer because `UserPreferences` (a widget-shared model) stores it;
/// UI presentation (`label`/`symbol`) is an app-side extension in Theme.swift.
enum ThemeMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
}

/// Day-of-week identity for a habit's rest-day schedule. Raw values match
/// `Calendar.component(.weekday)` (1 = Sunday … 7 = Saturday) and are persisted
/// as a bitmask on `Habit.activeDaysMask` — shared with the widget target, so
/// never reorder.
enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }
    var bit: Int { 1 << (rawValue - 1) }

    var shortLabel: String {
        switch self {
        case .sunday:    "S"
        case .monday:    "M"
        case .tuesday:   "T"
        case .wednesday: "W"
        case .thursday:  "T"
        case .friday:    "F"
        case .saturday:  "S"
        }
    }
}

/// Where a habit's streak stands *right now*, so UI can distinguish a streak
/// that is safe from one that still needs today's log.
enum HabitStreakState {
    /// No streak running.
    case none
    /// Today is already logged.
    case safe
    /// Streak is alive but today is an active day that hasn't been logged yet.
    case atRisk
    /// Today is a scheduled rest day — the streak carries over untouched.
    case rest
}

struct HabitDayEntry: Identifiable {
    let id: Date
    let date: Date
    let count: Int
}

struct HabitWeekSummary {
    var name: String
    var type: HabitType
    var weekTotal: Int
    var priorWeekTotal: Int
}

enum EventSource: String, Codable {
    // Stored on Event — append new cases only, never reorder.
    case manual, ai, imported, template
}

struct RecurrenceRule: Codable, Equatable {
    enum Frequency: String, Codable, CaseIterable {
        // Shared with the widget target — append new cases only, never reorder.
        case daily, weekly, monthly, yearly
    }
    var frequency: Frequency
    var interval: Int       // e.g. 2 = every 2 weeks
    var endDate: Date?
}

struct TimeBlock: Codable {
    var startHour: Int      // 0–23
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var weekdays: [Int]     // 1 = Sunday … 7 = Saturday; empty = every day
}
