import Foundation
import WidgetKit

/// Orchestrates the weekly meal scheduling pass:
/// breakfast scheduling → dinner scheduling → optional AI new-meal suggestion →
/// notification wiring → widget update.
///
/// Call `runWeeklyPass` on app launch and whenever the schedule changes.
@MainActor
final class MealPlanningCoordinator {

    private let mealScheduler = MealSchedulerService()
    private let notifications = NotificationService()
    private let aiService: AIService
    private let mealCategory: Category?

    init(aiService: AIService, mealCategory: Category?) {
        self.aiService = aiService
        self.mealCategory = mealCategory
    }

    /// Full weekly meal scheduling pass. Returns the newly created events so the caller
    /// can insert them into the SwiftData context.
    func runWeeklyPass(
        existingEvents: [Event],
        allMeals: [Meal],
        preferences: UserPreferences
    ) async -> WeeklyPassResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }

        var newEvents: [Event] = []

        // 1. Breakfast
        let breakfastEvents = mealScheduler.scheduleBreakfastIfNeeded(
            existingEvents: existingEvents,
            preferences: preferences,
            targetDates: targetDates
        )
        for event in breakfastEvents {
            event.category = mealCategory
            let identifier = notifications.scheduleMealNotification(for: event, reminderMinutes: preferences.defaultReminderMinutes)
            event.notificationIdentifier = identifier
        }
        newEvents.append(contentsOf: breakfastEvents)

        // Check breakfast missed streak
        let streak = mealScheduler.breakfastMissedStreakCount(events: existingEvents + breakfastEvents)
        if streak >= 3 {
            notifications.scheduleBreakfastMissedNudge(
                breakfastHour: preferences.breakfastHour,
                breakfastMinute: preferences.breakfastMinute
            )
        } else {
            notifications.cancelBreakfastMissedNudge()
        }

        // 2. Dinner — use knownMealIDs to filter the meal list
        let knownMealSet = Set(preferences.knownMealIDs)
        let cookableMeals = allMeals.filter { knownMealSet.contains($0.id) }
        let allExistingForDinner = existingEvents + breakfastEvents
        let dinnerEvents = mealScheduler.scheduleDinnerSlots(
            existingEvents: allExistingForDinner,
            meals: cookableMeals,
            preferences: preferences,
            targetDates: targetDates
        )
        for event in dinnerEvents {
            event.category = mealCategory
            let identifier = notifications.scheduleMealNotification(for: event, reminderMinutes: preferences.defaultReminderMinutes)
            event.notificationIdentifier = identifier
        }
        newEvents.append(contentsOf: dinnerEvents)

        // 3. AI new-meal suggestion (once per week)
        var newMeal: Meal?
        var newMealEvent: Event?

        if preferences.newMealSuggestionEnabled && shouldSuggestNewMeal(preferences: preferences) {
            let freeDinnerSlots = mealScheduler.remainingDinnerSlots(
                for: targetDates,
                existingEvents: allExistingForDinner,
                scheduledDinnerEvents: dinnerEvents,
                preferences: preferences
            )
            if !freeDinnerSlots.isEmpty {
                do {
                    let result = try await aiService.suggestNewMeal(
                        existingMeals: allMeals,
                        freeDinnerSlots: freeDinnerSlots,
                        preferences: preferences,
                        referenceWeek: targetDates
                    )
                    let suggestedEvent = Event(
                        title: result.meal.name,
                        startTime: result.scheduledStart,
                        endTime: result.scheduledEnd,
                        category: mealCategory,
                        source: .ai
                    )
                    let identifier = notifications.scheduleMealNotification(
                        for: suggestedEvent,
                        reminderMinutes: preferences.defaultReminderMinutes
                    )
                    suggestedEvent.notificationIdentifier = identifier
                    newMeal = result.meal
                    newMealEvent = suggestedEvent
                    newEvents.append(suggestedEvent)
                    // NOTE: meal.id is NOT added to knownMealIDs here.
                    // It joins the rotation only once the user marks the event .completed.
                    preferences.lastNewMealSuggestedDate = Date()
                } catch {
                    // Suggestion failures are non-fatal; regular rotation continues.
                }
            }
        }

        // 4. Widget — nearest upcoming meal
        let allMealEvents = existingEvents + newEvents
        if let nearest = mealScheduler.nearestUpcomingMeal(from: allMealEvents) {
            var widgetData = ScheduleWidgetData.load() ?? ScheduleWidgetData(
                lastUpdated: Date(),
                upcomingEvents: [],
                todayCompleted: 0,
                todayTotal: 0,
                nextMeal: nil
            )
            widgetData.nextMeal = WidgetEvent(
                title: nearest.title,
                startTime: nearest.startTime,
                categoryColorHex: nearest.category?.colorHex ?? "#F0AD4E"
            )
            widgetData.save()
            WidgetCenter.shared.reloadAllTimelines()
        }

        return WeeklyPassResult(
            newEvents: newEvents,
            newMeal: newMeal,
            newMealEvent: newMealEvent
        )
    }

    // MARK: - Private

    private func shouldSuggestNewMeal(preferences: UserPreferences) -> Bool {
        guard let last = preferences.lastNewMealSuggestedDate else { return true }
        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return daysSince >= 7
    }
}

struct WeeklyPassResult {
    var newEvents: [Event]
    var newMeal: Meal?
    var newMealEvent: Event?
}
