import Foundation

/// Presentation strings for the streak state — shared by the habit card, the
/// detail screen, and anywhere else a streak is surfaced, so they never drift.
extension Habit {

    private var dayNoun: String { currentStreak == 1 ? "day" : "days" }

    var streakHeadline: String {
        switch streakState {
        case .none:   return "Start your streak today"
        case .safe:   return "\(currentStreak) \(dayNoun)"
        case .atRisk: return "\(currentStreak) \(dayNoun) — keep it alive today"
        case .rest:   return "\(currentStreak) \(dayNoun) — rest day"
        }
    }

    var streakSymbol: String {
        switch streakState {
        case .none, .atRisk: return "flame"
        case .safe, .rest:   return "flame.fill"
        }
    }
}
