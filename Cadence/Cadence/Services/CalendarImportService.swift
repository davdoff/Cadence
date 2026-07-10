import Foundation
import SwiftData

/// One concrete, already-expanded occurrence from any import source —
/// EventKitReader (device calendars) and ICSImporter (feed URLs) both
/// produce these, so a single dedupe pass serves every source kind.
struct ImportedEventInstance {
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let externalIdentifier: String   // stable per occurrence across re-syncs
    let categoryHint: String         // calendar title or feed name (§3.3 mapping)
}

/// Calendar import orchestration (calendar-import.md §3–§4): runs sync passes
/// over the user's connected sources, deduping on externalIdentifier scoped
/// to importSourceID, and owns the tombstone rule so locally deleted imports
/// don't come back on the next sync.
@MainActor
final class CalendarImportService {

    static let shared = CalendarImportService()
    private init() {}

    /// Always sync within a bounded window — never "all events ever" (§3.4).
    static let syncWindowDays = 90

    private var lastSyncAt: Date?

    // MARK: - Sync triggers

    /// Cheap guard for .EKEventStoreChanged: device calendars only (that's
    /// what the signal is about), only when access is already granted. Never
    /// prompts. Debounced, since EKEventStoreChanged fires in bursts.
    func syncIfAuthorized(context: ModelContext) {
        guard EventKitReader.shared.hasFullAccess else { return }
        if let last = lastSyncAt, Date.now.timeIntervalSince(last) < 5 { return }
        Task { await sync(kinds: [.deviceCalendar], context: context) }
    }

    /// Full pass over every enabled source: device calendars and feed URLs.
    /// Used at launch, on "Sync now", and after connecting/enabling a source.
    func syncAll(context: ModelContext) async {
        await sync(kinds: [.deviceCalendar, .subscriptionURL], context: context)
    }

    private func sync(kinds: Set<CalendarImportSource.Kind>, context: ModelContext) async {
        let sources = allSources(context: context).filter { kinds.contains($0.kind) && $0.isEnabled }
        guard !sources.isEmpty else { return }
        lastSyncAt = .now

        let window = Self.syncWindow()
        let prefs = fetchPrefs(context: context)
        var changed = false
        for source in sources {
            switch source.kind {
            case .deviceCalendar:
                guard EventKitReader.shared.hasFullAccess else { continue }
                let instances = EventKitReader.shared.events(
                    inCalendarsWithIdentifiers: [source.identifier],
                    window: window
                )
                changed = apply(instances, to: source, window: window, prefs: prefs, context: context) || changed
                source.lastSyncedAt = .now
            case .subscriptionURL:
                // Feed re-sync needs the server reachable (§4 trade-off): on
                // failure skip the source — no deletions, lastSyncedAt stays
                // stale so the UI shows the sync didn't happen.
                guard let result = try? await ICSImporter().importFeed(urlString: source.identifier, window: window) else { continue }
                changed = apply(result.instances, to: source, window: window, prefs: prefs, context: context) || changed
                source.lastSyncedAt = .now
            case .icsFile:
                continue // one-off file import: not implemented yet
            }
        }
        try? context.save()
        if changed { WidgetSync.refresh() }
    }

    // MARK: - Connect a feed (§4)

    /// Connects an .ics subscription URL: fetch + expand FIRST, so a bad URL
    /// never creates a source, then insert the source and apply its events.
    @discardableResult
    func connectFeed(urlString: String, context: ModelContext) async throws -> CalendarImportSource {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let window = Self.syncWindow()
        let result = try await ICSImporter().importFeed(urlString: trimmed, window: window)

        let source = CalendarImportSource(
            kind: .subscriptionURL,
            displayName: result.feedName ?? (URL(string: trimmed)?.host ?? trimmed),
            identifier: trimmed   // importSourceID for its events (§4.3)
        )
        context.insert(source)
        _ = apply(result.instances, to: source, window: window, prefs: fetchPrefs(context: context), context: context)
        source.lastSyncedAt = .now
        try? context.save()
        WidgetSync.refresh()
        return source
    }

    // MARK: - The shared dedupe pass

    /// Applies one source's fetched instances to the local store. Returns
    /// true when anything was inserted, updated, or deleted.
    private func apply(
        _ instances: [ImportedEventInstance],
        to source: CalendarImportSource,
        window: DateInterval,
        prefs: UserPreferences,
        context: ModelContext
    ) -> Bool {
        let existing = importedEvents(from: source, context: context)
        let byExternalID = Dictionary(existing.map { ($0.externalIdentifier ?? "", $0) },
                                      uniquingKeysWith: { first, _ in first })
        let tombstones = Set(source.deletedExternalIdentifiers)
        let notifications = NotificationService()
        var categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var changed = false

        var fetchedIDs = Set<String>()
        for instance in instances {
            // All-day events don't block time slots, so importing them would
            // only pollute the schedule and the free-slot finder (§3.1, §6).
            if instance.isAllDay { continue }
            // The user deleted this import locally — don't resurrect it (§5.1).
            if tombstones.contains(instance.externalIdentifier) { continue }
            fetchedIDs.insert(instance.externalIdentifier)

            if let event = byExternalID[instance.externalIdentifier] {
                changed = update(event, from: instance, prefs: prefs, notifications: notifications) || changed
            } else {
                insert(instance, source: source, prefs: prefs, notifications: notifications,
                       categories: &categories, context: context)
                changed = true
            }
        }

        // Removed (or moved out of the window) at the source: drop the local
        // copy — pending only. .completed/.missed is the user's history, and
        // .displaced is the planner's work in progress; neither may vanish.
        for event in existing where !fetchedIDs.contains(event.externalIdentifier ?? "") {
            guard event.startTime >= window.start, event.startTime <= window.end else { continue }
            guard event.status == .pending else { continue }
            notifications.cancelEventNotifications(for: event)
            context.delete(event)
            changed = true
        }
        return changed
    }

    private func insert(
        _ instance: ImportedEventInstance,
        source: CalendarImportSource,
        prefs: UserPreferences,
        notifications: NotificationService,
        categories: inout [Category],
        context: ModelContext
    ) {
        let event = Event(
            title: instance.title,
            startTime: instance.start,
            endTime: instance.end,
            category: category(forHint: instance.categoryHint, in: &categories, context: context),
            source: .imported,
            externalIdentifier: instance.externalIdentifier,
            importSourceID: source.identifier
        )
        // Occurrences arrive already expanded — store instances, never the rule.
        event.recurrenceRule = nil
        context.insert(event)
        schedule(event, prefs: prefs, notifications: notifications)
    }

    /// Re-sync rule (§1): update title/times in place, preserve status —
    /// never overwrite a .completed/.missed the user set. Returns true if
    /// anything actually differed.
    private func update(
        _ event: Event,
        from instance: ImportedEventInstance,
        prefs: UserPreferences,
        notifications: NotificationService
    ) -> Bool {
        let timeChanged = event.startTime != instance.start || event.endTime != instance.end
        let titleChanged = event.title != instance.title
        guard timeChanged || titleChanged else { return false }

        event.title = instance.title
        if timeChanged {
            event.startTime = instance.start
            event.endTime = instance.end
            // Changed events get their reminders rebuilt (§3.4 / README §8).
            notifications.cancelEventNotifications(for: event)
            if event.status == .pending || event.status == .displaced {
                schedule(event, prefs: prefs, notifications: notifications)
            }
        }
        return true
    }

    /// Same notification set AddEventView schedules for a manual event.
    private func schedule(_ event: Event, prefs: UserPreferences, notifications: NotificationService) {
        guard notifications.isNotificationEnabled(for: event, prefs: prefs) else { return }
        event.notificationIdentifier = notifications.scheduleEventReminder(
            for: event, reminderMinutes: prefs.defaultReminderMinutes
        )
        notifications.scheduleEventStartAlert(for: event, reminderMinutes: prefs.defaultReminderMinutes)
        notifications.scheduleMissedEventAlert(for: event)
    }

    // MARK: - Category mapping (§3.3 — local only, never AI)

    /// Calendar title / feed name → existing category on a case-insensitive
    /// name match, else the shared "Imported" fallback (created on first use).
    /// `categories` is the caller's one-fetch-per-pass cache; a newly created
    /// "Imported" category is appended so later events in the pass reuse it.
    private func category(forHint hint: String, in categories: inout [Category], context: ModelContext) -> Category {
        if let match = categories.first(where: { $0.name.caseInsensitiveCompare(hint) == .orderedSame }) {
            return match
        }
        if let imported = categories.first(where: { $0.name == "Imported" }) {
            return imported
        }
        let imported = Category(name: "Imported", colorHex: "#8E8E93")
        context.insert(imported)
        categories.append(imported)
        return imported
    }

    // MARK: - Source management

    func allSources(context: ModelContext) -> [CalendarImportSource] {
        (try? context.fetch(FetchDescriptor<CalendarImportSource>(
            sortBy: [SortDescriptor(\.displayName)]
        ))) ?? []
    }

    /// Removes a source and every event imported from it.
    func removeSource(_ source: CalendarImportSource, context: ModelContext) {
        let notifications = NotificationService()
        for event in importedEvents(from: source, context: context) {
            notifications.cancelEventNotifications(for: event)
            context.delete(event)
        }
        context.delete(source)
        try? context.save()
        WidgetSync.refresh()
    }

    /// Call BEFORE deleting an imported event anywhere in the app: records a
    /// tombstone on its source so the next sync doesn't re-insert it (§5.1).
    func noteLocalDeletion(of event: Event, context: ModelContext) {
        guard event.source == .imported,
              let externalID = event.externalIdentifier,
              let sourceID = event.importSourceID
        else { return }
        guard let source = allSources(context: context).first(where: { $0.identifier == sourceID }),
              !source.deletedExternalIdentifiers.contains(externalID)
        else { return }
        source.deletedExternalIdentifiers.append(externalID)
    }

    // MARK: - Helpers

    private static func syncWindow() -> DateInterval {
        DateInterval(
            start: .now,
            end: Calendar.current.date(byAdding: .day, value: syncWindowDays, to: .now) ?? .now
        )
    }

    private func fetchPrefs(context: ModelContext) -> UserPreferences {
        (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first ?? UserPreferences()
    }

    private func importedEvents(from source: CalendarImportSource, context: ModelContext) -> [Event] {
        let sourceID = source.identifier
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.importSourceID == sourceID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
