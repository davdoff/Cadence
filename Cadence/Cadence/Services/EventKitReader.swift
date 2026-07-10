import Foundation
import EventKit

/// Pure EventKit access (calendar-import.md §2–§3): iOS 17+ permission flow
/// and fetching device-calendar events as expanded occurrences. Covers every
/// account iOS surfaces (Google, Outlook, iCloud, Exchange, subscriptions).
/// Returns plain value types only — applying them to SwiftData is
/// CalendarImportService's job.
final class EventKitReader {

    /// One EKEventStore instance, reused app-wide.
    static let shared = EventKitReader()
    private let store = EKEventStore()
    private init() {}

    var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// True when we can still ask (no prompt has been shown yet).
    var canRequestAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    /// iOS 17+ permission flow. Reading requires FULL access — `.writeOnly`
    /// cannot fetch, so it counts as denied (send the user to Settings).
    func ensureAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        case .writeOnly, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Every event calendar on the device, for the in-app picker — the OS
    /// grant is all-or-nothing across calendars, ours shouldn't be (§2).
    func deviceCalendars() -> [EKCalendar] {
        guard hasFullAccess else { return [] }
        return store.calendars(for: .event)
    }

    /// Expanded occurrences from the given calendars within a bounded window.
    /// events(matching:) already flattens recurring events into concrete
    /// instances with timezones resolved — exactly the shape Event wants (§3.1).
    func events(inCalendarsWithIdentifiers ids: Set<String>, window: DateInterval) -> [ImportedEventInstance] {
        guard hasFullAccess else { return [] }
        let calendars = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: calendars
        )
        return store.events(matching: predicate).compactMap { ek in
            guard let start = ek.startDate, let end = ek.endDate, let calendar = ek.calendar else { return nil }
            return ImportedEventInstance(
                title: ek.title ?? "Untitled",
                start: start,
                end: end,
                isAllDay: ek.isAllDay,
                externalIdentifier: Self.stableInstanceIdentifier(for: ek),
                categoryHint: calendar.title
            )
        }
    }

    // MARK: - Identity

    private static let occurrenceFormatter = ISO8601DateFormatter()

    /// calendarItemExternalIdentifier is stable across devices (preferred over
    /// eventIdentifier) but SHARED by every occurrence of a recurring event —
    /// suffix the original occurrence date so each expanded instance dedupes
    /// independently on re-sync. occurrenceDate stays fixed even when a single
    /// occurrence is detached and moved, keeping the identifier stable.
    private static func stableInstanceIdentifier(for ek: EKEvent) -> String {
        let base = ek.calendarItemExternalIdentifier
            ?? ek.eventIdentifier
            ?? "\(ek.title ?? "?")@\(ek.startDate?.timeIntervalSince1970 ?? 0)"
        guard ek.hasRecurrenceRules || ek.isDetached else { return base }
        let occurrence = ek.occurrenceDate ?? ek.startDate ?? .distantPast
        return base + "#" + occurrenceFormatter.string(from: occurrence)
    }
}
