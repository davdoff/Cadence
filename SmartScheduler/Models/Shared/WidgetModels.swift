import Foundation

// Add this file to BOTH the app target and the widget extension target in Xcode's File Inspector.

struct WidgetEvent: Codable {
    var title: String
    var startTime: Date
    var categoryColorHex: String
}

struct ScheduleWidgetData: Codable {
    var lastUpdated: Date
    var upcomingEvents: [WidgetEvent]   // keep to 5 max
    var todayCompleted: Int
    var todayTotal: Int
    var nextMeal: WidgetEvent?

    static let appGroupKey = "scheduleWidgetData"
    static let appGroupID  = "group.com.yourname.smartscheduler"

    static func load() -> ScheduleWidgetData? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: appGroupKey)
        else { return nil }
        return try? JSONDecoder().decode(ScheduleWidgetData.self, from: data)
    }

    func save() {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: Self.appGroupKey)
    }
}
