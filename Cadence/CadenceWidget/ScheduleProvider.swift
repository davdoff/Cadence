import WidgetKit
import Foundation

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let pending: [EventSnapshot]
    let completed: Int
    let total: Int
    let accentHex: String
}

extension ScheduleEntry {
    /// Sample data for the widget gallery.
    static var placeholder: ScheduleEntry {
        let now = Date()
        return ScheduleEntry(
            date: now,
            pending: [
                EventSnapshot(id: UUID(), title: "Deep work", startTime: now.addingTimeInterval(3600),
                              endTime: now.addingTimeInterval(7200), colorHex: "#4A90E2"),
                EventSnapshot(id: UUID(), title: "Gym", startTime: now.addingTimeInterval(10800),
                              endTime: now.addingTimeInterval(14400), colorHex: "#5CB85C"),
                EventSnapshot(id: UUID(), title: "Dinner", startTime: now.addingTimeInterval(18000),
                              endTime: now.addingTimeInterval(21600), colorHex: "#F0AD4E")
            ],
            completed: 3, total: 7,
            accentHex: WidgetTheme.accentHex
        )
    }
}

/// Shared by the Next Events, Daily Progress, and Today's Schedule widgets.
/// One entry now plus one at each remaining event's start/end, so "up next"
/// flips exactly on time without waking the app.
struct ScheduleProvider: TimelineProvider {

    func placeholder(in context: Context) -> ScheduleEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date()
        let (pending, completed, total) = WidgetDataStore.todaysEvents(now: now)
        let accent = WidgetTheme.accentHex

        var dates: Set<Date> = [now]
        for event in pending {
            if event.startTime > now { dates.insert(event.startTime) }
            dates.insert(event.endTime)
        }
        let entries = dates.sorted().prefix(12).map { date in
            ScheduleEntry(
                date: date,
                pending: pending.filter { $0.endTime > date },
                completed: completed,
                total: total,
                accentHex: accent
            )
        }

        let midnight = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
        )!
        completion(Timeline(entries: Array(entries), policy: .after(midnight)))
    }

    private func entry(at date: Date) -> ScheduleEntry {
        let (pending, completed, total) = WidgetDataStore.todaysEvents(now: date)
        return ScheduleEntry(date: date, pending: pending, completed: completed,
                             total: total, accentHex: WidgetTheme.accentHex)
    }
}
