import Foundation

enum SchedulingIntent {
    case mealSuggestion(existingMeals: [Meal], freeDinnerSlots: [TimeSlot])
}

struct SchedulingContextBuilder {

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func build(_ intent: SchedulingIntent, preferences: UserPreferences) -> String {
        switch intent {
        case .mealSuggestion(let meals, let slots):
            return buildMealSuggestion(meals: meals, slots: slots, preferences: preferences)
        }
    }

    // MARK: - Private

    private func buildMealSuggestion(
        meals: [Meal],
        slots: [TimeSlot],
        preferences: UserPreferences
    ) -> String {
        let mealsLine = meals
            .map { "\($0.name)(\($0.prepTimeMinutes)min)" }
            .joined(separator: ", ")

        let slotsLine = slots
            .map { slot in
                let day  = Self.dayFmt.string(from: slot.start).uppercased()
                let from = Self.timeFmt.string(from: slot.start)
                let to   = Self.timeFmt.string(from: slot.end)
                return "\(day) \(from)-\(to)"
            }
            .joined(separator: ", ")

        let winStart = String(format: "%02d:%02d", preferences.dinnerWindowStartHour, preferences.dinnerWindowStartMinute)
        let winEnd   = String(format: "%02d:%02d", preferences.dinnerWindowEndHour,   preferences.dinnerWindowEndMinute)

        return """
        INTENT: new_meal_suggestion
        EXISTING_MEALS: \(mealsLine)
        FREE_DINNER_SLOTS: \(slotsLine)
        PREFS: dinnerWindow=\(winStart)-\(winEnd)
        """
    }
}
