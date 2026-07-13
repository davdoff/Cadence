import Foundation
import SwiftData

/// Which occurrences a bulk occurrence-edit touches. `.thisAndFuture` mirrors
/// the rule-change semantics (this occurrence + later pending ones, history
/// untouched); `.all` rewrites every occurrence in the series, past included.
/// Surfaced in the edit sheet only after the user opts into "change all".
enum SeriesEditScope: Hashable {
    case thisAndFuture
    case all
}

/// Native recurring events: owns `EventSeries` rows and materializes their
/// occurrences as real `Event` rows within a rolling horizon — the same
/// store-instances-not-rules shape the calendar import uses, so the
/// scheduler, per-occurrence statuses, notifications, and widgets all work
/// on plain events. Imported recurring events are NOT materialized here
/// (their source owns the rule); they only share the `seriesID` grouping.
@MainActor
final class RecurrenceService {

    static let shared = RecurrenceService()
    private init() {}

    /// Rolling materialization horizon (matches CalendarImportService.syncWindowDays).
    static let horizonDays = 90
    /// Yearly rules need a longer horizon or the next occurrence would only
    /// appear ~90 days before it happens.
    static let yearlyHorizonDays = 400
    /// iOS keeps only the 64 soonest pending local notifications — a daily
    /// 90-day series × 3 alerts would starve everything else. So series
    /// occurrences get their notifications only once they're this close;
    /// `topUp` back-fills at each launch.
    static let notificationLeadDays = 7

    // MARK: - Pure occurrence math

    static func horizon(for frequency: RecurrenceRule.Frequency,
                        from now: Date = .now,
                        calendar: Calendar = .current) -> Date {
        let days = frequency == .yearly ? yearlyHorizonDays : horizonDays
        return calendar.date(byAdding: .day, value: days, to: now) ?? now
    }

    /// Occurrence starts strictly after `after`, up to and including `until`.
    /// Each occurrence is computed as anchor + k·step via Calendar (wall-clock
    /// math, so times survive DST changes and monthly rules don't drift
    /// through short months).
    static func occurrenceStarts(
        rule: RecurrenceRule,
        anchor: Date,
        after: Date,
        until: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let step = max(1, rule.interval)
        let unit: Calendar.Component
        switch rule.frequency {
        case .daily:   unit = .day
        case .weekly:  unit = .weekOfYear
        case .monthly: unit = .month
        case .yearly:  unit = .year
        }
        var starts: [Date] = []
        var k = 1
        while k <= 10_000 {
            guard let next = calendar.date(byAdding: unit, value: k * step, to: anchor) else { break }
            if next > until { break }
            if let end = rule.endDate, next > end { break }
            if next > after { starts.append(next) }
            k += 1
        }
        return starts
    }

    // MARK: - Series lifecycle

    /// Turns a just-saved event into the anchor of a new series and
    /// materializes the remaining occurrences. Caller saves the context.
    func createSeries(from event: Event, rule: RecurrenceRule, context: ModelContext) {
        let series = EventSeries(
            rule: rule,
            title: event.title,
            anchorStart: event.startTime,
            duration: event.duration,
            category: event.category
        )
        context.insert(series)
        event.seriesID = series.id.uuidString
        materialize(series, context: context)
        scheduleNearNotifications(context: context)
    }

    /// Extends every series to its horizon and schedules notifications for
    /// occurrences entering the near window. Called at app launch.
    func topUp(context: ModelContext) {
        let allSeries = (try? context.fetch(FetchDescriptor<EventSeries>())) ?? []
        var changed = false
        for series in allSeries {
            changed = materialize(series, context: context) || changed
        }
        scheduleNearNotifications(context: context)
        try? context.save()
        if changed { WidgetSync.refresh() }
    }

    /// Rule change from the edit sheet — applies to this occurrence and all
    /// future ones: the edited occurrence becomes the new anchor/template,
    /// later pending occurrences are regenerated under the new rule. Past
    /// occurrences and completed/missed history are never touched.
    func updateRule(from occurrence: Event, to rule: RecurrenceRule, context: ModelContext) {
        guard let series = series(for: occurrence, context: context) else { return }
        removeFuturePending(seriesID: series.id.uuidString, after: occurrence, context: context)
        series.rule = rule
        series.title = occurrence.title
        series.category = occurrence.category
        series.anchorStart = occurrence.startTime
        series.duration = occurrence.duration
        series.materializedUntil = occurrence.startTime
        materialize(series, context: context)
        scheduleNearNotifications(context: context)
    }

    /// Propagates an occurrence-level edit (title, category, time-of-day,
    /// duration) from `occurrence` across its native series. Each affected
    /// occurrence keeps its own calendar day but adopts the edited time-of-day
    /// and duration; title and category are copied as-is. The series template
    /// is updated so future materialization matches. Notifications for affected
    /// occurrences are rebuilt via the near-window scheduler. Occurrence
    /// statuses are left untouched, so `.all` never rewrites completed history
    /// into pending. No-op for imported series (no EventSeries row). Caller
    /// saves the context.
    func applyOccurrenceEdit(
        from occurrence: Event,
        scope: SeriesEditScope,
        title: String,
        category: Category?,
        startTimeOfDay: DateComponents,
        duration: TimeInterval,
        context: ModelContext
    ) {
        guard let series = series(for: occurrence, context: context) else { return }
        let calendar = Calendar.current
        let notifications = NotificationService()
        let hour = startTimeOfDay.hour ?? 0
        let minute = startTimeOfDay.minute ?? 0

        let affected = events(seriesID: series.id.uuidString, context: context).filter { event in
            switch scope {
            case .all:           return true
            case .thisAndFuture: return event.id == occurrence.id || event.startTime > occurrence.startTime
            }
        }

        for event in affected {
            event.title = title
            event.category = category
            guard let newStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: event.startTime)
            else { continue }
            if event.startTime != newStart || event.duration != duration {
                event.startTime = newStart
                event.endTime = newStart.addingTimeInterval(duration)
                // Drop scheduled notifications; the near-window pass re-adds the
                // ones that still qualify (respecting the 64-notification cap).
                if event.notificationIdentifier != nil {
                    notifications.cancelEventNotifications(for: event)
                    event.notificationIdentifier = nil
                }
            }
        }

        // Update the template so future materialization matches the edit.
        series.title = title
        series.category = category
        if let anchorStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: series.anchorStart) {
            series.anchorStart = anchorStart
        }
        series.duration = duration

        scheduleNearNotifications(context: context)
    }

    /// Rule set back to "Never": the series ends with this occurrence.
    /// Future pending occurrences are removed; this one and the past keep
    /// their seriesID so history stays grouped.
    func endSeries(from occurrence: Event, context: ModelContext) {
        guard let series = series(for: occurrence, context: context) else { return }
        removeFuturePending(seriesID: series.id.uuidString, after: occurrence, context: context)
        series.endDate = occurrence.startTime
    }

    /// "Delete this and all future events." Deletes the given occurrence and
    /// every later pending one. Native series get their endDate capped so
    /// top-up never regenerates them; imported series record tombstones so
    /// the next sync (and the sliding window) doesn't re-insert them.
    /// Saves and refreshes — call sites treat it like a delete.
    func deleteFuture(from occurrence: Event, context: ModelContext) {
        guard let seriesID = occurrence.seriesID else { return }
        let notifications = NotificationService()
        let nativeSeries = series(for: occurrence, context: context)

        if let nativeSeries {
            nativeSeries.endDate = occurrence.startTime.addingTimeInterval(-1)
        } else {
            // Imported series: one tombstone covers the whole tail, including
            // occurrences the sliding sync window hasn't fetched yet.
            CalendarImportService.shared.noteLocalSeriesDeletion(of: occurrence, context: context)
        }

        var doomed = futurePending(seriesID: seriesID, after: occurrence, context: context)
        doomed.append(occurrence)
        for event in doomed {
            notifications.cancelEventNotifications(for: event)
            CalendarImportService.shared.noteLocalDeletion(of: event, context: context)
            context.delete(event)
        }

        // A native series with no occurrences left is gone entirely.
        if let nativeSeries, events(seriesID: seriesID, context: context).isEmpty {
            context.delete(nativeSeries)
        }
        try? context.save()
        WidgetSync.refresh()
    }

    // MARK: - Materialization

    /// Generates occurrences in (materializedUntil, horizon] and bumps the
    /// mark. Generating only past the high-water mark is what keeps locally
    /// deleted occurrences from being resurrected. Returns true if any
    /// occurrence was inserted.
    @discardableResult
    private func materialize(_ series: EventSeries, context: ModelContext) -> Bool {
        let horizon = Self.horizon(for: series.frequency)
        guard horizon > series.materializedUntil else { return false }
        let starts = Self.occurrenceStarts(
            rule: series.rule,
            anchor: series.anchorStart,
            after: series.materializedUntil,
            until: horizon
        )
        for start in starts {
            let event = Event(
                title: series.title,
                startTime: start,
                endTime: start.addingTimeInterval(series.duration),
                category: series.category
            )
            event.seriesID = series.id.uuidString
            context.insert(event)
        }
        series.materializedUntil = horizon
        return !starts.isEmpty
    }

    /// The AddEventView notification set for pending series occurrences that
    /// enter the near window (notificationIdentifier == nil marks "not yet
    /// scheduled").
    private func scheduleNearNotifications(context: ModelContext) {
        let now = Date.now
        guard let cutoff = Calendar.current.date(byAdding: .day, value: Self.notificationLeadDays, to: now)
        else { return }
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate {
            $0.seriesID != nil && $0.notificationIdentifier == nil
                && $0.startTime > now && $0.startTime <= cutoff
        })
        let upcoming = ((try? context.fetch(descriptor)) ?? []).filter { $0.status == .pending }
        guard !upcoming.isEmpty else { return }

        let prefs = (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first ?? UserPreferences()
        let notifications = NotificationService()
        for event in upcoming {
            guard notifications.isNotificationEnabled(for: event, prefs: prefs) else { continue }
            event.notificationIdentifier = notifications.scheduleEventReminder(
                for: event, reminderMinutes: prefs.defaultReminderMinutes
            )
            notifications.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
            notifications.scheduleMissedEventAlert(for: event)
        }
    }

    // MARK: - Lookups

    /// The native series an occurrence belongs to — nil for imported series
    /// (they have a seriesID but no EventSeries row).
    func series(for event: Event, context: ModelContext) -> EventSeries? {
        guard let raw = event.seriesID, let id = UUID(uuidString: raw) else { return nil }
        let descriptor = FetchDescriptor<EventSeries>(predicate: #Predicate { $0.id == id })
        return ((try? context.fetch(descriptor)) ?? []).first
    }

    private func events(seriesID: String, context: ModelContext) -> [Event] {
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.seriesID == seriesID })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func futurePending(seriesID: String, after occurrence: Event, context: ModelContext) -> [Event] {
        events(seriesID: seriesID, context: context).filter {
            $0.id != occurrence.id && $0.startTime > occurrence.startTime && $0.status == .pending
        }
    }

    private func removeFuturePending(seriesID: String, after occurrence: Event, context: ModelContext) {
        let notifications = NotificationService()
        for event in futurePending(seriesID: seriesID, after: occurrence, context: context) {
            notifications.cancelEventNotifications(for: event)
            context.delete(event)
        }
    }
}

// MARK: - Display

extension RecurrenceRule {
    /// "Every day", "Every 3 days", "Every 2 weeks · until Jan 5" — used by
    /// the detail view's Repeats card.
    var displayText: String {
        let unit: String
        switch frequency {
        case .daily:   unit = "day"
        case .weekly:  unit = "week"
        case .monthly: unit = "month"
        case .yearly:  unit = "year"
        }
        var text = interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)s"
        if let endDate {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            text += " · until \(f.string(from: endDate))"
        }
        return text
    }
}
