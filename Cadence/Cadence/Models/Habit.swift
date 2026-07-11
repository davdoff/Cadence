import SwiftData
import Foundation

@Model
final class Habit {
    var id: UUID
    var name: String
    var type: HabitType
    var correlatedCategoryName: String?
    var countLog: [String: Int]
    var symbolName: String = "star.fill"   // SF Symbol name
    var colorHex:   String = "#E8784D"     // widget-facing flat color; kept in
                                           //   sync with the tile's solid color
    // Per-habit tile-color identity (CADENCE_DESIGN_SYSTEM §5). A plain String
    // so this widget-shared model stays Foundation-only; must match a
    // `HabitTileColor` id. Declaration default migrates existing habits.
    var tileColorID: String = "orange"
    var dailyGoal:  Int    = 1             // 0 = no goal
    var weeklyGoal: Int    = 0             // 0 = no goal

    init(
        name: String,
        type: HabitType,
        correlatedCategoryName: String? = nil,
        symbolName: String? = nil,
        colorHex: String? = nil,
        tileColorID: String? = nil,
        dailyGoal: Int = 1,
        weeklyGoal: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.correlatedCategoryName = correlatedCategoryName
        self.countLog = [:]
        self.symbolName = symbolName ?? (type == .good ? "star.fill" : "bolt.slash.fill")
        self.colorHex   = colorHex   ?? (type == .good ? "#E8784D"  : "#E05252")
        self.tileColorID = tileColorID ?? "orange"
        self.dailyGoal  = type == .good ? max(dailyGoal, 0) : 0
        self.weeklyGoal = weeklyGoal
    }
}

// MARK: - Static icon / colour palettes

extension Habit {
    static let goodSymbols: [String] = [
        "star.fill", "flame.fill", "heart.fill", "bolt.heart.fill",
        "book.fill", "figure.run", "dumbbell.fill", "brain.head.profile",
        "moon.stars.fill", "drop.fill", "music.note", "leaf.fill",
        "pencil", "fork.knife", "bicycle", "sunrise.fill",
        "cup.and.saucer.fill", "paintbrush.fill", "lightbulb.fill", "trophy.fill"
    ]

    static let badSymbols: [String] = [
        "bolt.slash.fill", "xmark.circle.fill", "exclamationmark.triangle.fill",
        "wineglass", "gamecontroller.fill", "mug.fill", "cart.fill",
        "tv.fill", "zzz", "dollarsign.circle.fill", "nosign", "phone.fill"
    ]

    static let presetColors: [String] = [
        "#E8784D", "#E05252", "#E0528A", "#7B52E0",
        "#5278E0", "#52B4E0", "#52C47A", "#C4A232",
        "#E0A052", "#8B6651", "#6A6A6A", "#5A7A8A"
    ]
}

// MARK: - Date helpers

extension Habit {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { dateFormatter.string(from: date) }

    func count(for date: Date = .now) -> Int { countLog[Habit.key(for: date)] ?? 0 }

    func increment(for date: Date = .now) {
        let k = Habit.key(for: date)
        countLog[k, default: 0] += 1
    }

    func decrement(for date: Date = .now) {
        let k = Habit.key(for: date)
        let current = countLog[k, default: 0]
        if current > 0 { countLog[k] = current - 1 }
    }

    func weeklyTotal(days: Int = 7) -> Int {
        let calendar = Calendar.current
        return (0..<days).reduce(0) { sum, offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            return sum + count(for: date)
        }
    }

    func priorWeeklyTotal() -> Int {
        let calendar = Calendar.current
        return (7..<14).reduce(0) { sum, offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            return sum + count(for: date)
        }
    }

    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        for offset in 0...365 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            if count(for: date) > 0 { streak += 1 } else { break }
        }
        return streak
    }

    func countHistory(days: Int = 7) -> [HabitDayEntry] {
        let calendar = Calendar.current
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            return HabitDayEntry(id: date, date: date, count: count(for: date))
        }
    }

    func weekSummary() -> HabitWeekSummary {
        HabitWeekSummary(name: name, type: type, weekTotal: weeklyTotal(), priorWeekTotal: priorWeeklyTotal())
    }
}
