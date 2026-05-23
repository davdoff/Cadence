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

    @Relationship
    var category: Category?

    init(
        title: String,
        startTime: Date,
        endTime: Date,
        category: Category? = nil,
        source: EventSource = .manual
    ) {
        self.id = UUID()
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.status = .pending
        self.source = source
        self.category = category
    }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
    var isUpcoming: Bool { startTime > Date.now }
    var isInProgress: Bool { startTime <= Date.now && endTime > Date.now }
}
