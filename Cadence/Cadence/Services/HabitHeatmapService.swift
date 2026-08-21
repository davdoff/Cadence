import Foundation

/// One cell of a calendar-month heatmap. `date == nil` marks a leading padding
/// cell before the first of the month.
struct HabitHeatmapCell: Identifiable {
    let id: Int
    let date: Date?
    let count: Int
}

/// Lays out a calendar month as heatmap cells, week-aligned to the calendar's
/// first weekday. Pure computation — no SwiftData, no SwiftUI.
enum HabitHeatmapService {

    static func month(containing date: Date,
                      calendar: Calendar = .current,
                      count: (Date) -> Int) -> [HabitHeatmapCell] {
        guard
            let interval = calendar.dateInterval(of: .month, for: date),
            let dayCount = calendar.range(of: .day, in: .month, for: date)?.count
        else { return [] }

        let first = interval.start
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7

        var cells = (0..<leading).map { HabitHeatmapCell(id: $0, date: nil, count: 0) }
        for day in 0..<dayCount {
            guard let cellDate = calendar.date(byAdding: .day, value: day, to: first) else { continue }
            cells.append(HabitHeatmapCell(id: leading + day, date: cellDate, count: count(cellDate)))
        }
        return cells
    }

    /// Shading step (0 = empty, 1…3 = increasing intensity) for a day's count
    /// against the month's peak.
    static func level(count: Int, peak: Int) -> Int {
        guard count > 0 else { return 0 }
        guard peak > 1 else { return 3 }
        let ratio = Double(count) / Double(peak)
        if ratio > 0.66 { return 3 }
        if ratio > 0.33 { return 2 }
        return 1
    }
}
