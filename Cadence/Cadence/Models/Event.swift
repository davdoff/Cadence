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
}
