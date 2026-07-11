import SwiftData
import Foundation

@Model
final class UserPreferences {
    // Working hours
    var workStartHour: Int
    var workEndHour: Int
    var bufferMinutes: Int
    var avoidScheduling: [TimeBlock]
    var priorityCategoryIDs: [UUID]

    // Meals
    var mealsPerDay: Int

    // Breakfast
    var breakfastEnabled: Bool
    var breakfastHour: Int
    var breakfastMinute: Int
    var breakfastDuration: Int       // minutes, capped at 30

    // Dinner window
    var dinnerWindowStartHour: Int
    var dinnerWindowStartMinute: Int
    var dinnerWindowEndHour: Int
    var dinnerWindowEndMinute: Int

    // Meal catalog
    var knownMealIDs: [UUID]
    var newMealSuggestionEnabled: Bool
    var lastNewMealSuggestedDate: Date?
    // Free-text guidance for AI meal suggestions (e.g. "vegetarian, more rice dishes").
    // Declaration default (not just init) so existing on-device stores migrate.
    var mealGuidance: String = ""
    // Daily cap on AI meal-suggestion fetches (declaration defaults for migration).
    var mealSuggestionFetchCount: Int = 0
    var mealSuggestionFetchDate: Date? = nil

    // AI behaviour: 1 = passive suggestions, 5 = aggressive scheduling
    var aiAggressiveness: Int

    // Visual theme override (CADENCE_DESIGN_SYSTEM §5). Durable record of the
    // Light/Dark/System choice; ContentView drives live rendering off the
    // mirrored @AppStorage("themeMode"). Declaration default for migration.
    var themeModeRaw: String = ThemeMode.system.rawValue

    // Notifications
    var notificationsEnabled: Bool
    var defaultReminderMinutes: Int
    // Stored as JSON-encoded Data because SwiftData doesn't persist [UUID: Bool] directly
    var perCategoryNotificationsData: Data

    // Pre-formatted string sent to Claude API; regenerate only when prefs change
    var compactPreferenceString: String

    init() {
        workStartHour = 9
        workEndHour = 18
        bufferMinutes = 15
        avoidScheduling = []
        priorityCategoryIDs = []
        mealsPerDay = 3
        aiAggressiveness = 3
        notificationsEnabled = true
        defaultReminderMinutes = 15
        perCategoryNotificationsData = Data()
        compactPreferenceString = ""
        breakfastEnabled = true
        breakfastHour = 8
        breakfastMinute = 0
        breakfastDuration = 30
        dinnerWindowStartHour = 19
        dinnerWindowStartMinute = 0
        dinnerWindowEndHour = 22
        dinnerWindowEndMinute = 0
        knownMealIDs = []
        newMealSuggestionEnabled = true
        lastNewMealSuggestedDate = nil
        mealGuidance = ""
        mealSuggestionFetchCount = 0
        mealSuggestionFetchDate = nil
    }

    // MARK: - Meal suggestion fetch cap

    static let maxMealSuggestionFetchesPerDay = 2

    func canFetchMealSuggestion(now: Date = Date()) -> Bool {
        guard let date = mealSuggestionFetchDate,
              Calendar.current.isDate(date, inSameDayAs: now) else { return true }
        return mealSuggestionFetchCount < Self.maxMealSuggestionFetchesPerDay
    }

    func recordMealSuggestionFetch(now: Date = Date()) {
        if let date = mealSuggestionFetchDate, Calendar.current.isDate(date, inSameDayAs: now) {
            mealSuggestionFetchCount += 1
        } else {
            mealSuggestionFetchCount = 1
        }
        mealSuggestionFetchDate = now
    }

    func perCategoryNotifications() -> [UUID: Bool] {
        (try? JSONDecoder().decode([UUID: Bool].self, from: perCategoryNotificationsData)) ?? [:]
    }

    func setPerCategoryNotifications(_ dict: [UUID: Bool]) {
        perCategoryNotificationsData = (try? JSONEncoder().encode(dict)) ?? Data()
    }
}
