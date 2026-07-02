import Foundation
import WidgetKit

/// Orchestrates the daily meal scheduling pass for today only:
/// stale future-meal cleanup → breakfast scheduling → dinner scheduling →
/// notification wiring → widget update. AI meal suggestions are user-triggered
/// from WeeklyMealsView, not part of this pass.
///
/// Meals are planned at day start rather than a week ahead, so they never
/// block future timeslots. Call `runDailyPass` on app launch and whenever
/// a new day begins.
@MainActor
final class MealPlanningCoordinator {

    private let mealScheduler = MealSchedulerService()
    private let notifications = NotificationService()
    private let mealCategory: Category?

    init(mealCategory: Category?) {
        self.mealCategory = mealCategory
    }

    /// Daily meal scheduling pass for today. Returns the newly created events so the caller
    /// can insert them into the SwiftData context, plus stale future meal events to delete.
    func runDailyPass(
        existingEvents: [Event],
        allMeals: [Meal],
        preferences: UserPreferences
    ) -> DailyPassResult {
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

        // 3. Widget — nearest upcoming meal
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
            eventsToDelete: staleFutureMeals
        )
    }
}

struct DailyPassResult {
    var newEvents: [Event]
    var eventsToDelete: [Event]
}
