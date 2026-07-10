import SwiftData
import Foundation

/// A calendar the user has connected for import (calendar-import.md §1):
/// a device calendar today, an .ics subscription URL or one-off file later.
/// Lets the Preferences screen list and remove sources, and carries the
/// tombstones that stop re-syncs from resurrecting locally deleted imports.
@Model
final class CalendarImportSource {
    var id: UUID
    var kindRaw: String
    var displayName: String     // e.g. "Work (Google)" or "Uni Timetable"
    var identifier: String      // EKCalendar.calendarIdentifier OR the feed URL
    var lastSyncedAt: Date?
    var isEnabled: Bool
    // externalIdentifiers the user deleted locally — the sync pass skips
    // re-inserting these (calendar-import.md §5.1 note).
    var deletedExternalIdentifiers: [String]

    enum Kind: String, Codable {
        case deviceCalendar, subscriptionURL, icsFile
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .deviceCalendar }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: Kind, displayName: String, identifier: String) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.displayName = displayName
        self.identifier = identifier
        self.lastSyncedAt = nil
        self.isEnabled = true
        self.deletedExternalIdentifiers = []
    }
}
