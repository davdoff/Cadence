import SwiftUI
import SwiftData
import Charts

struct OverviewView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var habits: [Habit]

    @State private var period: StatsPeriod = .week

    enum StatsPeriod: String, CaseIterable {
        case week = "This Week", month = "This Month"
    }

    // MARK: - Date window

    private var periodStart: Date {
        let cal = Calendar.current
        switch period {
        case .week:
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now
        case .month:
            return cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        }
    }

    // .displaced is excluded everywhere: the planner moved those aside, the user
    // didn't fail them — they must not drag down completion/missed stats.
    private var periodEvents: [Event] {
        allEvents.filter { $0.startTime >= periodStart && $0.status != .displaced }
    }

    // MARK: - Stats

    private var completed: Int { periodEvents.filter { $0.status == .completed }.count }
    private var missed:    Int { periodEvents.filter { $0.status == .missed    }.count }
    private var upcoming:  Int { periodEvents.filter { $0.status == .pending && $0.startTime > .now }.count }
    private var total:     Int { periodEvents.count }
    private var rate:    Double { total > 0 ? Double(completed) / Double(total) : 0 }

    // MARK: - Category stats

    private struct CatStat: Identifiable {
        let id = UUID()
        let name: String
        let colorHex: String
        let completed: Int
        let total: Int
        var completionRate: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    private var categoryStats: [CatStat] {
        var map: [String: (hex: String, done: Int, all: Int)] = [:]
        for event in periodEvents {
            let key = event.category?.name ?? "Uncategorised"
            let hex = event.category?.colorHex ?? "#AAAAAA"
            var e = map[key] ?? (hex, 0, 0)
            e.all += 1
            if event.status == .completed { e.done += 1 }
            map[key] = e
        }
        return map.map { CatStat(name: $0.key, colorHex: $0.value.hex, completed: $0.value.done, total: $0.value.all) }
            .sorted { $0.completed > $1.completed }
    }

    // MARK: - Perfect days (all non-pending events completed)

    private var perfectDaysThisPeriod: Int {
        let cal = Calendar.current
        let days: Int = period == .week ? 7 : 30
        var count = 0
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: .now), day >= periodStart else { continue }
            let dayStart = cal.startOfDay(for: day)
            let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let dayEvents = allEvents.filter { $0.startTime >= dayStart && $0.startTime < dayEnd && $0.startTime < .now }
            if !dayEvents.isEmpty && dayEvents.allSatisfy({ $0.status == .completed }) { count += 1 }
        }
        return count
    }

    // MARK: - Meal stats

    private var mealEvents: [Event] {
        periodEvents.filter { $0.category?.name == "Meal" }
    }

    private var mealsEaten:  Int { mealEvents.filter { $0.status == .completed }.count }
    private var mealsMissed: Int { mealEvents.filter { $0.status == .missed    }.count }

    private var breakfastRate: Double? {
        let breakfasts = mealEvents.filter { $0.title == "Breakfast" && $0.status != .pending }
        guard !breakfasts.isEmpty else { return nil }
        return Double(breakfasts.filter { $0.status == .completed }.count) / Double(breakfasts.count)
    }

    // MARK: - Habit highlights

    private var goodHabits: [Habit] { habits.filter { $0.type == .good } }
    private var bestStreak: Habit?  { goodHabits.max { $0.currentStreak < $1.currentStreak } }
    private var totalLoggedToday: Int { goodHabits.reduce(0) { $0 + $1.count() } }

    // MARK: - Day-by-day chart data

    private struct DayStat: Identifiable {
        let id: Date
        let date: Date
        let completed: Int
        let missed: Int
    }

    private var dailyStats: [DayStat] {
        let cal  = Calendar.current
        let days = period == .week ? 7 : 30
        return (0..<days).reversed().compactMap { offset -> DayStat? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: .now),
                  day >= periodStart else { return nil }
            let start = cal.startOfDay(for: day)
            let end   = cal.date(byAdding: .day, value: 1, to: start)!
            let slice = allEvents.filter { $0.startTime >= start && $0.startTime < end }
            return DayStat(
                id: day,
                date: day,
                completed: slice.filter { $0.status == .completed }.count,
                missed:    slice.filter { $0.status == .missed    }.count
            )
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appBackground(accentColorHex).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    periodPicker
                    completionRingCard
                    statsRow
                    if total > 0 {
                        activityChartCard
                    }
                    if !categoryStats.isEmpty {
                        categoryCard
                    }
                    if !mealEvents.isEmpty {
                        mealsCard
                    }
                    if !habits.isEmpty {
                        habitsCard
                    }
                    if total == 0 && habits.isEmpty {
                        emptyState
                    }
                }
                .padding()
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Completion ring

    private var completionRingCard: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.appDeep(accentColorHex), lineWidth: 18)
                    .frame(width: 170, height: 170)

                // Fill arc
                Circle()
                    .trim(from: 0, to: rate)
                    .stroke(
                        LinearGradient(
                            colors: [.accentLight(accentColorHex), .appAccent(accentColorHex), .accentDark(accentColorHex)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.75), value: rate)

                // Center label
                VStack(spacing: 2) {
                    Text("\(Int(rate * 100))%")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.appAccent(accentColorHex))
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: rate)
                    Text("completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text(period.rawValue)
                    .font(.subheadline.weight(.medium))
                if total > 0 {
                    Text("·").foregroundColor(.secondary)
                    Text("\(total) event\(total == 1 ? "" : "s")")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                if perfectDaysThisPeriod > 0 {
                    Text("·").foregroundColor(.secondary)
                    Label("\(perfectDaysThisPeriod) perfect day\(perfectDaysThisPeriod == 1 ? "" : "s")", systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.appAccent(accentColorHex))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    // MARK: - Stats chips

    private var statsRow: some View {
        HStack(spacing: 12) {
            statChip(value: completed, label: "Completed", icon: "checkmark.circle.fill", color: .green)
            statChip(value: missed,    label: "Missed",    icon: "xmark.circle.fill",     color: .red.opacity(0.7))
            statChip(value: upcoming,  label: "Coming up", icon: "clock.fill",            color: .accentLight(accentColorHex))
        }
    }

    private func statChip(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundColor(color)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: value)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Activity chart

    private var activityChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.subheadline.weight(.semibold))

            Chart(dailyStats) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Total", day.completed + day.missed)
                )
                .foregroundStyle(Color.appDeep(accentColorHex))
                .cornerRadius(4)

                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Done", day.completed)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentLight(accentColorHex), .appAccent(accentColorHex)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 7)) { _ in
                    AxisValueLabel(
                        format: period == .week ? .dateTime.weekday(.narrow) : .dateTime.day()
                    )
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 120)

            HStack(spacing: 16) {
                legendDot(color: .appAccent(accentColorHex),    label: "Completed")
                legendDot(color: .appDeep(accentColorHex), label: "Missed / Total")
            }
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Category breakdown

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By Category")
                .font(.subheadline.weight(.semibold))

            ForEach(categoryStats) { stat in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Circle()
                            .fill(Color(hex: stat.colorHex))
                            .frame(width: 9, height: 9)
                        Text(stat.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(stat.completed)/\(stat.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("(\(Int(stat.completionRate * 100))%)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(stat.completionRate >= 0.7 ? .green : .secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.appDeep(accentColorHex))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: stat.colorHex).opacity(0.8))
                                .frame(width: geo.size.width * stat.completionRate)
                                .animation(.easeOut(duration: 0.4), value: stat.completionRate)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: - Meals card

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Meals", systemImage: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.appAccent(accentColorHex))

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(mealsEaten)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.appAccent(accentColorHex))
                    Text("meal\(mealsEaten == 1 ? "" : "s") eaten")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .center, spacing: 4) {
                    Text("\(mealsMissed)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(mealsMissed > 0 ? .red.opacity(0.7) : .secondary)
                    Text("missed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if let rate = breakfastRate {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(rate * 100))%")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(rate >= 0.7 ? .green : .appAccent(accentColorHex))
                        Text("breakfasts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: - Habits highlight

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Habits Today", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.appAccent(accentColorHex))

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalLoggedToday)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.appAccent(accentColorHex))
                    Text("good action\(totalLoggedToday == 1 ? "" : "s") logged")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let best = bestStreak, best.currentStreak > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(best.currentStreak)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.appAccent(accentColorHex))
                            Text("days").font(.caption).foregroundColor(.secondary)
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill").foregroundColor(.appAccent(accentColorHex))
                            Image(systemName: best.symbolName)
                            Text(best.name)
                        }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // Mini habit list
            let topHabits = goodHabits.prefix(3)
            if !topHabits.isEmpty {
                Divider()
                ForEach(Array(topHabits)) { habit in
                    HStack {
                        Image(systemName: habit.symbolName)
                            .font(.subheadline)
                            .foregroundColor(Color(hex: habit.colorHex))
                        Text(habit.name).font(.subheadline)
                        Spacer()
                        if habit.dailyGoal > 0 {
                            let p = min(Double(habit.count()) / Double(habit.dailyGoal), 1.0)
                            Text("\(habit.count())/\(habit.dailyGoal)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(p >= 1 ? .green : .appAccent(accentColorHex))
                        } else {
                            Text("\(habit.count())")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.appAccent(accentColorHex))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.pie")
                .font(.system(size: 52))
                .foregroundColor(.accentLight(accentColorHex))
            Text("Nothing to show yet")
                .font(.headline).foregroundColor(.secondary)
            Text("Add events and habits — your stats will appear here.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
