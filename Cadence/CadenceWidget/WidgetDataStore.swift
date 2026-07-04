import Foundation
import SwiftData

/// Value-type snapshots for timeline entries — @Model objects must never
/// leave the fetch context.
struct EventSnapshot: Identifiable {
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let colorHex: String
}

struct HabitSnapshot: Identifiable {
    let id: UUID
    let name: String
    let symbolName: String
    let colorHex: String
    let todayCount: Int
    let dailyGoal: Int
    let weekCount: Int
    let weeklyGoal: Int
}

/// Read-only access to the shared App Group SwiftData store for the
/// widget timeline providers. Writes happen only in `IncrementHabitIntent`.
enum WidgetDataStore {

    static let container = SharedModelContainer.make()

    /// Today's events: pending ones still ahead (sorted), plus completed/total counts.
    static func todaysEvents(now: Date = .now) -> (pending: [EventSnapshot], completed: Int, total: Int) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.startTime >= dayStart && $0.startTime < dayEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let events = (try? context.fetch(descriptor)) ?? []
        let pending = events
            .filter { $0.status == .pending && $0.endTime > now }
            .map { snapshot(of: $0) }
        let completed = events.filter { $0.status == .completed }.count
        return (pending, completed, events.count)
    }

    /// Nearest pending Meal-category event that hasn't started yet.
    static func nextMeal(now: Date = .now) -> EventSnapshot? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.startTime > now },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let events = (try? context.fetch(descriptor)) ?? []
        return events
            .first { $0.status == .pending && $0.category?.name == "Meal" }
            .map { snapshot(of: $0) }
    }

    /// Good habits only — goal rings are meaningless for bad habits, which have no goals.
    static func allHabits() -> [HabitSnapshot] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.name)])
        let habits = (try? context.fetch(descriptor)) ?? []
        return habits.filter { $0.type == .good }.map { snapshot(of: $0) }
    }

    static func habit(id: UUID) -> HabitSnapshot? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first.map { snapshot(of: $0) }
    }

    // MARK: - Mapping

    private static func snapshot(of event: Event) -> EventSnapshot {
        EventSnapshot(
            id: event.id,
            title: event.title,
            startTime: event.startTime,
            endTime: event.endTime,
            colorHex: event.category?.colorHex ?? WidgetTheme.accentHex
        )
    }

    private static func snapshot(of habit: Habit) -> HabitSnapshot {
        HabitSnapshot(
            id: habit.id,
            name: habit.name,
            symbolName: habit.symbolName,
            colorHex: habit.colorHex,
            todayCount: habit.count(),
            dailyGoal: habit.dailyGoal,
            weekCount: habit.weeklyTotal(),
            weeklyGoal: habit.weeklyGoal
        )
    }
}
