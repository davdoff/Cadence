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

/// Manual light/dark override (CADENCE_DESIGN_SYSTEM §5). Lives in the shared
/// model layer because `UserPreferences` (a widget-shared model) stores it;
/// UI presentation (`label`/`symbol`) is an app-side extension in Theme.swift.
enum ThemeMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
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
    case manual, ai, imported
}

struct RecurrenceRule: Codable {
    enum Frequency: String, Codable {
        case daily, weekly, monthly
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
