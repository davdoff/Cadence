import SwiftData
import Foundation

/// One native recurring-event series. Occurrences are real `Event` rows
/// (tagged with `seriesID == id.uuidString`) materialized by
/// `RecurrenceService` within a rolling horizon — mirroring how calendar
/// import stores pre-expanded instances, so the scheduler, notifications,
/// per-occurrence statuses, and widgets all work on plain events.
///
/// Imported recurring events have NO EventSeries row: their source calendar
/// owns the rule and the expansion; they only share the `seriesID` grouping.
@Model
final class EventSeries {
    var id: UUID
    var frequencyRaw: String
    var interval: Int           // e.g. 2 = every 2 days/weeks/months/years
    var endDate: Date?          // nil = repeats until deleted

    // Template for generating occurrences. anchorStart is the first
    // occurrence's start and carries the time-of-day; occurrence-level edits
    // (title/time of a single event) never touch the template.
    var title: String
    var anchorStart: Date
    var duration: TimeInterval

    // High-water mark: top-up only generates occurrences strictly after this,
    // so locally deleted occurrences are never resurrected on the next pass.
    var materializedUntil: Date

    @Relationship
    var category: Category?

    var frequency: RecurrenceRule.Frequency {
        get { RecurrenceRule.Frequency(rawValue: frequencyRaw) ?? .weekly }
        set { frequencyRaw = newValue.rawValue }
    }

    var rule: RecurrenceRule {
        get { RecurrenceRule(frequency: frequency, interval: interval, endDate: endDate) }
        set {
            frequency = newValue.frequency
            interval = newValue.interval
            endDate = newValue.endDate
        }
    }

    init(rule: RecurrenceRule, title: String, anchorStart: Date, duration: TimeInterval, category: Category? = nil) {
        self.id = UUID()
        self.frequencyRaw = rule.frequency.rawValue
        self.interval = max(1, rule.interval)
        self.endDate = rule.endDate
        self.title = title
        self.anchorStart = anchorStart
        self.duration = duration
        self.materializedUntil = anchorStart
        self.category = category
    }
}
