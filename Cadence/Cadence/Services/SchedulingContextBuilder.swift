import Foundation

enum SchedulingIntent {
    case mealSuggestion(existingMeals: [Meal], freeDinnerSlots: [TimeSlot])
    case addToFreeSlot(description: String, freeSlots: [TimeSlot])
    case moveEvent(event: Event, reason: String, surroundingEvents: [Event], freeSlots: [TimeSlot])
    case rescheduleMissed(event: Event, missedCount: Int, freeSlots: [TimeSlot])
    case habitWeeklyAnalysis(habits: [HabitWeekSummary])
    case deepProjectPlan(goal: String, deadline: Date, weeklyHours: Int, constraints: String)
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

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let nowFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    func build(_ intent: SchedulingIntent, preferences: UserPreferences) -> String {
        let now = "NOW: \(Self.nowFmt.string(from: Date.now))"
        let body: String
        switch intent {
        case .mealSuggestion(let meals, let slots):
            body = buildMealSuggestion(meals: meals, slots: slots, preferences: preferences)
        case .addToFreeSlot(let description, let freeSlots):
            body = buildAddToFreeSlot(description: description, freeSlots: freeSlots, preferences: preferences)
        case .moveEvent(let event, let reason, let surrounding, let freeSlots):
            body = buildMoveEvent(event: event, reason: reason, surroundingEvents: surrounding, freeSlots: freeSlots, preferences: preferences)
        case .rescheduleMissed(let event, let missedCount, let freeSlots):
            body = buildRescheduleMissed(event: event, missedCount: missedCount, freeSlots: freeSlots, preferences: preferences)
        case .habitWeeklyAnalysis(let habits):
            body = buildHabitAnalysis(habits: habits)
        case .deepProjectPlan(let goal, let deadline, let weeklyHours, let constraints):
            body = buildDeepProjectPlan(goal: goal, deadline: deadline, weeklyHours: weeklyHours, constraints: constraints)
        }
        return "\(now)\n\(body)"
    }

    // MARK: - Builders

    private func buildMealSuggestion(
        meals: [Meal],
        slots: [TimeSlot],
        preferences: UserPreferences
    ) -> String {
        let mealsLine = meals
            .map { "\($0.name)(\($0.prepTimeMinutes)min)" }
            .joined(separator: ", ")
        let slotsLine = slots.map { slotLabel($0) }.joined(separator: ", ")
        let winStart = String(format: "%02d:%02d", preferences.dinnerWindowStartHour, preferences.dinnerWindowStartMinute)
        let winEnd   = String(format: "%02d:%02d", preferences.dinnerWindowEndHour,   preferences.dinnerWindowEndMinute)
        return """
        INTENT: new_meal_suggestion
        EXISTING_MEALS: \(mealsLine)
        FREE_DINNER_SLOTS: \(slotsLine)
        PREFS: dinnerWindow=\(winStart)-\(winEnd)
        """
    }

    private func buildAddToFreeSlot(
        description: String,
        freeSlots: [TimeSlot],
        preferences: UserPreferences
    ) -> String {
        let slotsLine = freeSlots.map { slotLabel($0) }.joined(separator: ", ")
        return """
        FREE_SLOTS: \(slotsLine)
        NEW_EVENT: "\(description)"
        PREFS: BufferBetweenEvents=\(preferences.bufferMinutes)min
        """
    }

    private func buildMoveEvent(
        event: Event,
        reason: String,
        surroundingEvents: [Event],
        freeSlots: [TimeSlot],
        preferences: UserPreferences
    ) -> String {
        let cat = event.category?.name ?? "—"
        let anchor = "\(event.title) | \(dayLabel(event.startTime)) \(timeRange(event)) | category=\(cat)"
        let surrounding = surroundingEvents.map { e in
            "\(dayLabel(e.startTime)) \(timeRange(e))[\(e.category?.name ?? "—")]"
        }.joined(separator: " ")
        let slotsLine = freeSlots.map { slotLabel($0) }.joined(separator: ", ")
        return """
        ANCHOR_EVENT: \(anchor)
        SURROUNDING_EVENTS: \(surrounding.isEmpty ? "none" : surrounding)
        FREE_SLOTS: \(slotsLine)
        REASON_FOR_MOVE: "\(reason)"
        PREFS: BufferBetweenEvents=\(preferences.bufferMinutes)min
        """
    }

    private func buildRescheduleMissed(
        event: Event,
        missedCount: Int,
        freeSlots: [TimeSlot],
        preferences: UserPreferences
    ) -> String {
        let was = "\(dayLabel(event.startTime)) \(timeRange(event))"
        let slotsLine = freeSlots.map { slotLabel($0) }.joined(separator: ", ")
        return """
        MISSED_EVENT: \(event.title) | WAS: \(was) | missed_count=\(missedCount)
        FREE_SLOTS (next 7d): \(slotsLine)
        PREFS: BufferBetweenEvents=\(preferences.bufferMinutes)min
        """
    }

    private func buildHabitAnalysis(habits: [HabitWeekSummary]) -> String {
        let habitsLine = habits.map { s in
            let trend = s.weekTotal > s.priorWeekTotal ? "↑" : (s.weekTotal < s.priorWeekTotal ? "↓" : "→")
            return "\(s.name)=\(s.weekTotal)(\(trend) from \(s.priorWeekTotal))"
        }.joined(separator: ", ")
        return "HABITS_WEEK: \(habitsLine)"
    }

    private func buildDeepProjectPlan(
        goal: String,
        deadline: Date,
        weeklyHours: Int,
        constraints: String
    ) -> String {
        let deadlineStr = Self.dateFmt.string(from: deadline)
        return """
        GOAL: "\(goal)"
        DEADLINE: \(deadlineStr)
        WEEKLY_HOURS: \(weeklyHours)
        CONSTRAINTS: "\(constraints)"
        """
    }

    // MARK: - Formatting helpers

    private func slotLabel(_ slot: TimeSlot) -> String {
        let day  = Self.dayFmt.string(from: slot.start).uppercased()
        let from = Self.timeFmt.string(from: slot.start)
        let to   = Self.timeFmt.string(from: slot.end)
        return "\(day) \(from)-\(to)"
    }

    private func dayLabel(_ date: Date) -> String {
        Self.dayFmt.string(from: date).uppercased()
    }

    private func timeRange(_ event: Event) -> String {
        "\(Self.timeFmt.string(from: event.startTime))-\(Self.timeFmt.string(from: event.endTime))"
    }
}
