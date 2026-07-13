import SwiftData
import Foundation

@Model
final class Event {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var status: EventStatus
    var source: EventSource
    var recurrenceRule: RecurrenceRule?
    var notificationIdentifier: String?
    // Calendar import (calendar-import.md §1) — nil for manual/AI events.
    // externalIdentifier: ICS UID or EventKit occurrence identifier, used to
    // dedupe on re-sync. importSourceID: which feed/calendar this came from,
    // enabling "remove all events from this source".
    var externalIdentifier: String?
    var importSourceID: String?
    // Set when the user taps "Start" on the event in Today. Drives the live
    // in-progress countdown; nil until started. Defaulted inline so existing
    // rows migrate to nil without a schema change.
    var startedAt: Date? = nil
    // Groups the occurrences of a recurring event. Native series: the
    // EventSeries.id (RecurrenceService owns generation). Imported series:
    // the source's base identifier — no EventSeries row, the source calendar
    // owns the rule. Defaulted inline for lightweight migration.
    var seriesID: String? = nil

    @Relationship
    var category: Category?

    init(
        title: String,
        startTime: Date,
        endTime: Date,
        category: Category? = nil,
        source: EventSource = .manual,
        externalIdentifier: String? = nil,
        importSourceID: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.status = .pending
        self.source = source
        self.category = category
        self.externalIdentifier = externalIdentifier
        self.importSourceID = importSourceID
    }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
    var isUpcoming: Bool { startTime > Date.now }
    var isInProgress: Bool { startTime <= Date.now && endTime > Date.now }

    /// True while a manually-started event's timer is still relevant (started
    /// and not yet marked complete/missed).
    var isRunning: Bool { startedAt != nil && status == .pending }
    /// Whether the Start affordance should be offered. Completed events are
    /// excluded (starting one wouldn't track correctly) and already-running
    /// events don't re-start; pending / missed / displaced are all startable.
    var canStart: Bool { status != .completed && !isRunning }
    /// When a started event's countdown completes: the planned duration measured
    /// from the moment Start was tapped (not the scheduled end).
    var finishTime: Date? { startedAt.map { $0.addingTimeInterval(duration) } }
    /// One occurrence of a recurring event (native or imported).
    var isRecurring: Bool { seriesID != nil }
}
