import Foundation
import WidgetKit

/// Orchestrates the daily meal scheduling pass for today only:
/// stale future-meal cleanup → breakfast scheduling → dinner scheduling →
/// optional AI new-meal suggestion → notification wiring → widget update.
///
/// Meals are planned at day start rather than a week ahead, so they never
/// block future timeslots. Call `runDailyPass` on app launch and whenever
/// a new day begins.
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

    /// Daily meal scheduling pass for today. Returns the newly created events so the caller
    /// can insert them into the SwiftData context, plus stale future meal events to delete.
    func runDailyPass(
        existingEvents: [Event],
        allMeals: [Meal],
        preferences: UserPreferences
    ) async -> DailyPassResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDates = [today]

        // 0. Cleanup — pending AI meal events on future days (leftovers from the old
        // week-ahead planning). Cancel their notifications and hand them back for deletion.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let staleFutureMeals = existingEvents.filter {
            $0.source == .ai &&
            $0.status == .pending &&
            $0.category?.name == "Meal" &&
            $0.startTime >= tomorrow
        }
        for event in staleFutureMeals {
            notifications.cancelEventNotifications(for: event)
        }
        let remainingEvents = existingEvents.filter { event in
            !staleFutureMeals.contains { $0.id == event.id }
        }

        var newEvents: [Event] = []

        // 1. Breakfast
        let breakfastEvents = mealScheduler.scheduleBreakfastIfNeeded(
            existingEvents: remainingEvents,
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
        let streak = mealScheduler.breakfastMissedStreakCount(events: remainingEvents + breakfastEvents)
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
        let allExistingForDinner = remainingEvents + breakfastEvents
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

        // 3. AI new-meal suggestion (once per week, placed in today's free dinner slots)
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
        let allMealEvents = remainingEvents + newEvents
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

        return DailyPassResult(
            newEvents: newEvents,
            eventsToDelete: staleFutureMeals,
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

struct DailyPassResult {
    var newEvents: [Event]
    var eventsToDelete: [Event]
    var newMeal: Meal?
    var newMealEvent: Event?
}
