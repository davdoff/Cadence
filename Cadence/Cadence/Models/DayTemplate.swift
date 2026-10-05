import SwiftData
import Foundation

// Day templates (day-templates.md): reusable day layouts stamped onto dates
// locally — no AI call. Blocks are stored as minute-of-day offsets, never
// absolute dates, so a template lands on any day. Every stored property has
// an inline default so adding these models is a lightweight migration
// (SharedModelContainer wipes the store if a migration ever fails).

@Model
final class DayTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var symbolName: String? = nil
    var blocks: [TemplateBlock] = []
    var createdAt: Date = Date.now
    var lastUsedDate: Date? = nil

    init(name: String, symbolName: String? = nil, blocks: [TemplateBlock] = []) {
        self.id = UUID()
        self.name = name
        self.symbolName = symbolName
        self.blocks = blocks
        self.createdAt = .now
    }

    /// Blocks in start-time order — the order the planner places them in.
    var sortedBlocks: [TemplateBlock] { blocks.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay } }
}

struct TemplateBlock: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var startMinuteOfDay: Int       // 0–1439, e.g. 7:30 → 450
    var durationMinutes: Int
    var categoryName: String        // matched to a Category by name on apply
}

/// A weekday → day-template mapping ("Mon–Fri = Work day, Sat = Sporty day").
/// Points at day templates by id, so deleting a day template just leaves that
/// weekday empty instead of cascading.
@Model
final class WeekTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var assignments: [WeekdayAssignment] = []

    init(name: String, assignments: [WeekdayAssignment] = []) {
        self.id = UUID()
        self.name = name
        self.assignments = assignments
    }

    func templateID(forWeekday weekday: Int) -> UUID? {
        assignments.first { $0.weekday == weekday }?.templateID
    }
}

struct WeekdayAssignment: Codable, Hashable {
    var weekday: Int                // Calendar weekday: 1 = Sunday … 7 = Saturday
    var templateID: UUID
}
