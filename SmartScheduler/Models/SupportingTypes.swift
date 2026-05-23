import Foundation

enum EventStatus: String, Codable {
    case pending, completed, missed
}

enum EventSource: String, Codable {
    case manual, ai, imported
}

struct RecurrenceRule: Codable {
    enum Frequency: String, Codable {
        case daily, weekly, monthly
    }
    var frequency: Frequency
    var interval: Int       // e.g. 2 = every 2 weeks
    var endDate: Date?
}

struct TimeBlock: Codable {
    var startHour: Int      // 0–23
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var weekdays: [Int]     // 1 = Sunday … 7 = Saturday; empty = every day
}
