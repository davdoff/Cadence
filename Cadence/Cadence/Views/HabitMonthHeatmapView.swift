import SwiftUI

/// GitHub-style month heatmap of a habit's daily counts.
struct HabitMonthHeatmapView: View {
    @Environment(\.theme) private var theme
    let habit: Habit
    let color: Color

    @State private var monthAnchor: Date = .now

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var cells: [HabitHeatmapCell] {
        HabitHeatmapService.month(containing: monthAnchor, calendar: calendar) { habit.count(for: $0) }
    }
    private var peak: Int { cells.map(\.count).max() ?? 0 }

    private var weekdayInitials: [String] {
        (0..<7).map { offset in
            let index = (calendar.firstWeekday - 1 + offset) % 7
            return String(calendar.veryShortStandaloneWeekdaySymbols[index])
        }
    }

    private var monthTitle: String {
        monthAnchor.formatted(.dateTime.month(.wide).year())
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: monthAnchor) else { return false }
        return next <= Date.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayInitials.indices, id: \.self) { i in
                    Text(weekdayInitials[i])
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                ForEach(cells) { cell in
                    dayCell(cell)
                }
            }
            legend
        }
        .padding()
        .cardStyle()
    }

    private var header: some View {
        HStack {
            Label("Month", systemImage: "square.grid.3x3.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
            Spacer()
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.caption.weight(.bold))
            }
            Text(monthTitle)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .frame(minWidth: 96)
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
        }
        .foregroundColor(color)
    }

    @ViewBuilder
    private func dayCell(_ cell: HabitHeatmapCell) -> some View {
        if let date = cell.date {
            let level = HabitHeatmapService.level(count: cell.count, peak: peak)
            let isToday = calendar.isDateInToday(date)
            RoundedRectangle(cornerRadius: 4)
                .fill(level == 0 ? AnyShapeStyle(theme.deep) : AnyShapeStyle(color.opacity(fillOpacity(level))))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isToday ? color : .clear, lineWidth: 1.5)
                )
                .overlay(
                    Group {
                        if !habit.isActiveDay(date) && level == 0 {
                            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 3, height: 3)
                        }
                    }
                )
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.system(size: 9)).foregroundColor(.secondary)
            ForEach(0..<4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(level == 0 ? AnyShapeStyle(theme.deep) : AnyShapeStyle(color.opacity(fillOpacity(level))))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundColor(.secondary)
            Spacer()
            if !habit.isEveryDaySchedule {
                Label("Rest day", systemImage: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func fillOpacity(_ level: Int) -> Double {
        switch level {
        case 3:  return 1.0
        case 2:  return 0.65
        default: return 0.32
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        if delta > 0 && shifted > Date.now { return }
        withAnimation(.easeInOut(duration: 0.2)) { monthAnchor = shifted }
    }
}
