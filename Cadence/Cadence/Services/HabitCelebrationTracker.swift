import Foundation

/// Remembers which habits have already celebrated their daily goal today, so the
/// burst fires once per habit per day instead of on every increment past the goal.
enum HabitCelebrationTracker {

    private static let prefix = "habitGoalCelebrated-"

    private static func key(for habitID: UUID) -> String { prefix + habitID.uuidString }

    /// True the first time a habit reaches its goal on `date`; false afterwards.
    static func claimCelebration(habitID: UUID, on date: Date = .now,
                                 store: UserDefaults = .standard) -> Bool {
        let dayKey = Habit.key(for: date)
        guard store.string(forKey: key(for: habitID)) != dayKey else { return false }
        store.set(dayKey, forKey: key(for: habitID))
        return true
    }

    static func reset(habitID: UUID, store: UserDefaults = .standard) {
        store.removeObject(forKey: key(for: habitID))
    }
}
