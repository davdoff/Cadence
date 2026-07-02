import Foundation

struct MealSchedulerService {

    // MARK: - Breakfast

    /// Returns new breakfast Events to persist for each day in targetDates that needs one.
    /// Skips days that already have a breakfast event, a conflicting event within 30 minutes,
    /// or a breakfast time that has already passed.
    func scheduleBreakfastIfNeeded(
        existingEvents: [Event],
        preferences: UserPreferences,
        targetDates: [Date],
        now: Date = Date()
    ) -> [Event] {
        guard preferences.breakfastEnabled else { return [] }
        let calendar = Calendar.current
        var newEvents: [Event] = []

        for date in targetDates {
            guard let start = calendar.date(
                bySettingHour: preferences.breakfastHour,
                minute: preferences.breakfastMinute,
                second: 0, of: date
            ) else { continue }

            if start < now { continue }

            let alreadyScheduled = existingEvents.contains {
                $0.title == "Breakfast" && calendar.isDate($0.startTime, inSameDayAs: date)
            }
            if alreadyScheduled { continue }

            let thirtyMin = TimeInterval(30 * 60)
            let hasConflict = existingEvents.contains {
                $0.status != .missed &&
                calendar.isDate($0.startTime, inSameDayAs: date) &&
                abs($0.startTime.timeIntervalSince(start)) < thirtyMin
            }
            if hasConflict { continue }

            let duration = TimeInterval(min(preferences.breakfastDuration, 30) * 60)
            let event = Event(title: "Breakfast", startTime: start, endTime: start.addingTimeInterval(duration), source: .ai)
            newEvents.append(event)
        }

        return newEvents
    }

    // MARK: - Dinner

    /// Returns new dinner Events to persist for each day in targetDates that has a free slot.
    /// Meal and slot selection are both random per spec. Respects bufferMinutes.
    func scheduleDinnerSlots(
        existingEvents: [Event],
        meals: [Meal],
        preferences: UserPreferences,
        targetDates: [Date],
        now: Date = Date()
    ) -> [Event] {
        guard !meals.isEmpty else { return [] }
        let calendar = Calendar.current
        var result: [Event] = []
        var allEvents = existingEvents

        for date in targetDates {
            guard
                let rawWindowStart = calendar.date(
                    bySettingHour: preferences.dinnerWindowStartHour,
                    minute: preferences.dinnerWindowStartMinute,
                    second: 0, of: date),
                let windowEnd = calendar.date(
                    bySettingHour: preferences.dinnerWindowEndHour,
                    minute: preferences.dinnerWindowEndMinute,
                    second: 0, of: date)
            else { continue }

            let dinnerExists = allEvents.contains {
                $0.status != .missed &&
                $0.source == .ai &&
                $0.startTime >= rawWindowStart &&
                $0.startTime < windowEnd
            }
            if dinnerExists { continue }

            let windowStart = Swift.max(rawWindowStart, now)
            guard windowStart < windowEnd else { continue }

            let meal = meals.randomElement()!
            let durationMinutes = meal.prepTimeMinutes > 0 ? meal.prepTimeMinutes : 45
            let required = TimeInterval(durationMinutes * 60)
            let buffer = TimeInterval(preferences.bufferMinutes * 60)

            let dayEvents = allEvents.filter {
                $0.status != .missed && calendar.isDate($0.startTime, inSameDayAs: date)
            }
            let slots = freeSlotsInWindow(
                windowStart: windowStart,
                windowEnd: windowEnd,
                blocking: dayEvents,
                required: required,
                buffer: buffer
            )
            guard let slot = slots.randomElement() else { continue }

            let end = Swift.min(slot.start.addingTimeInterval(required), windowEnd)
            let event = Event(title: meal.name, startTime: slot.start, endTime: end, source: .ai)
            result.append(event)
            allEvents.append(event)
        }

        return result
    }

    // MARK: - Free Slots After Dinner Scheduling

    /// Returns all unclaimed dinner-window slots across targetDates after accounting for
    /// existingEvents and already-scheduled dinner events.
    func remainingDinnerSlots(
        for dates: [Date],
        existingEvents: [Event],
        scheduledDinnerEvents: [Event],
        preferences: UserPreferences,
        minimumMinutes: Int = 45,
        now: Date = Date()
    ) -> [TimeSlot] {
        let calendar = Calendar.current
        let allEvents = existingEvents + scheduledDinnerEvents
        var slots: [TimeSlot] = []

        for date in dates {
            guard
                let rawWindowStart = calendar.date(
                    bySettingHour: preferences.dinnerWindowStartHour,
                    minute: preferences.dinnerWindowStartMinute,
                    second: 0, of: date),
                let windowEnd = calendar.date(
                    bySettingHour: preferences.dinnerWindowEndHour,
                    minute: preferences.dinnerWindowEndMinute,
                    second: 0, of: date)
            else { continue }

            let windowStart = Swift.max(rawWindowStart, now)
            guard windowStart < windowEnd else { continue }

            let dayEvents = allEvents.filter {
                $0.status != .missed && calendar.isDate($0.startTime, inSameDayAs: date)
            }
            let freeSlots = freeSlotsInWindow(
                windowStart: windowStart,
                windowEnd: windowEnd,
                blocking: dayEvents,
                required: TimeInterval(minimumMinutes * 60),
                buffer: TimeInterval(preferences.bufferMinutes * 60)
            )
            slots.append(contentsOf: freeSlots)
        }

        return slots
    }

    // MARK: - Streak Detection

    /// Counts consecutive missed breakfast events going backwards from today.
    func breakfastMissedStreakCount(events: [Event]) -> Int {
        let calendar = Calendar.current
        var checkDate = calendar.startOfDay(for: Date())
        var streak = 0

        for _ in 0..<30 {
            let dayBreakfasts = events.filter {
                $0.title == "Breakfast" && calendar.isDate($0.startTime, inSameDayAs: checkDate)
            }
            guard let breakfast = dayBreakfasts.first else { break }
            if breakfast.status == .missed {
                streak += 1
            } else {
                break
            }
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        return streak
    }

    // MARK: - Widget Helper

    /// Nearest upcoming meal event (breakfast or dinner) from now.
    func nearestUpcomingMeal(from events: [Event]) -> Event? {
        events
            .filter { $0.startTime > Date.now && $0.status == .pending }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    // MARK: - Private

    private func freeSlotsInWindow(
        windowStart: Date,
        windowEnd: Date,
        blocking events: [Event],
        required: TimeInterval,
        buffer: TimeInterval
    ) -> [TimeSlot] {
        var blocked = events.map {
            DateInterval(start: $0.startTime, end: $0.endTime.addingTimeInterval(buffer))
        }
        blocked.sort { $0.start < $1.start }

        var result: [TimeSlot] = []
        var cursor = windowStart

        for block in blocked {
            let bStart = Swift.max(block.start, windowStart)
            let bEnd   = Swift.min(block.end,   windowEnd)

            if bStart > cursor && bStart.timeIntervalSince(cursor) >= required {
                result.append(DateInterval(start: cursor, end: bStart))
            }
            if bEnd > cursor { cursor = bEnd }
        }

        if windowEnd > cursor && windowEnd.timeIntervalSince(cursor) >= required {
            result.append(DateInterval(start: cursor, end: windowEnd))
        }

        return result
    }
}
