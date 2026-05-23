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

    // AI behaviour: 1 = passive suggestions, 5 = aggressive scheduling
    var aiAggressiveness: Int

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
    }

    func perCategoryNotifications() -> [UUID: Bool] {
        (try? JSONDecoder().decode([UUID: Bool].self, from: perCategoryNotificationsData)) ?? [:]
    }

    func setPerCategoryNotifications(_ dict: [UUID: Bool]) {
        perCategoryNotificationsData = (try? JSONEncoder().encode(dict)) ?? Data()
    }
}
