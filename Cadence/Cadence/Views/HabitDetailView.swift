import SwiftUI
import SwiftData
import Charts

struct HabitDetailView: View {
    @Environment(\.theme) private var theme
    let habit: Habit
    @Environment(\.modelContext) private var context

    @State private var chartDays = 7
    @State private var aiAnalysis: String? = nil
    @State private var isAnalyzing = false
    @State private var analysisError: String? = nil

    /// Per-habit tile palette (§4/§5) for the active surface; `accent` is its
    /// icon color — the single flat hue used throughout the detail screen.
    private var tile:   HabitTileColor.Tokens { HabitTileColor.by(id: habit.tileColorID).tokens(dark: theme.isDark) }
    private var accent: Color { tile.icon }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    todayCard
                    if habit.type == .good { streakCard }
                    if habit.weeklyGoal > 0 { weeklyGoalCard }
                    chartCard
                    HabitMonthHeatmapView(habit: habit, color: accent)
                    if !weeklyMessages.isEmpty { insightsCard }
                    aiAnalysisCard
                }
                .padding()
            }
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tile.tileGradient)
                        .frame(width: 36, height: 36)
                    Image(systemName: habit.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tile.icon)
                }
            }
        }
    }

    // MARK: - Today card

    private var todayCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("\(habit.count())")
                        .font(.cadNumber(56))
                        .foregroundColor(accent)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25), value: habit.count())
                    Text(habit.type == .good ? "times" : "occurrences")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(duration: 0.2)) { habit.increment(); try? context.save() }
                        WidgetSync.refresh()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(tile.buttonGradient)
                    }
                    Button {
                        withAnimation(.spring(duration: 0.2)) { habit.decrement(); try? context.save() }
                        WidgetSync.refresh()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Color.gray.opacity(0.3))
                    }
                }
            }

            // Daily goal progress
            if habit.type == .good && habit.dailyGoal > 0 {
                let count = habit.count()
                let prog  = min(Double(count) / Double(habit.dailyGoal), 1.0)
                let done  = count >= habit.dailyGoal

                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack {
                        Label(
                            done ? "Daily goal complete!" : "\(count) / \(habit.dailyGoal) today",
                            systemImage: done ? "checkmark.circle.fill" : "target"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundColor(done ? .green : accent)
                        Spacer()
                        Text("\(Int(prog * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundColor(done ? .green : accent)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(theme.deep)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(done
                                      ? AnyShapeStyle(Color.green)
                                      : AnyShapeStyle(tile.buttonGradient))
                                .frame(width: geo.size.width * prog)
                                .animation(.easeOut(duration: 0.3), value: prog)
                        }
                    }
                    .frame(height: 7)
                }
            }

            // Streak / trend row
            Divider()
            if habit.type == .good {
                HStack {
                    Label(habit.streakHeadline, systemImage: habit.streakSymbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(habit.currentStreak > 0 ? accent : .secondary)
                    Spacer()
                    Text("This week: \(habit.weeklyTotal())")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "chart.line.downtrend.xyaxis").foregroundColor(.secondary)
                    Text("This week: \(habit.weeklyTotal())")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text("Last week: \(habit.priorWeeklyTotal())")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: accent.opacity(0.08), radius: 6, y: 2)
    }

    // MARK: - Streak card

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                streakStat(value: habit.currentStreak, label: "Current", symbol: habit.streakSymbol)
                Rectangle().fill(theme.deep).frame(width: 1, height: 40)
                streakStat(value: habit.bestStreak, label: "Best", symbol: "trophy.fill")
            }

            Text(streakStatusLine)
                .font(.caption)
                .foregroundColor(.secondary)

            if !habit.isEveryDaySchedule {
                Label(scheduleLine, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !Habit.streakMilestones.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Habit.streakMilestones, id: \.self) { milestone in
                        milestoneBadge(milestone)
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func streakStat(value: Int, label: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.footnote)
                Text("\(value)").font(.cadNumber(30)).contentTransition(.numericText())
            }
            .foregroundColor(value > 0 ? accent : .secondary)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func milestoneBadge(_ milestone: Int) -> some View {
        let earned = habit.earnedMilestones.contains(milestone)
        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(earned ? AnyShapeStyle(tile.buttonGradient) : AnyShapeStyle(theme.deep))
                    .frame(width: 38, height: 38)
                Image(systemName: earned ? "rosette" : "lock.fill")
                    .font(.system(size: earned ? 17 : 12, weight: .semibold))
                    .foregroundColor(earned ? .white : .secondary)
            }
            Text("\(milestone)d")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(earned ? accent : .secondary)
        }
        .opacity(earned ? 1 : 0.55)
    }

    private var streakStatusLine: String {
        switch habit.streakState {
        case .none:   return "Log it today to start a new run."
        case .safe:   return "Today is logged — the streak is safe."
        case .atRisk: return "Today isn't logged yet — one log keeps the run alive."
        case .rest:   return "Today is a scheduled rest day — your run carries over."
        }
    }

    private var scheduleLine: String {
        let days = Weekday.allCases.filter { habit.activeDays.contains($0) }
        return "Active on " + days.map(\.shortLabel).joined(separator: " ")
    }

    // MARK: - Weekly goal card

    private var weeklyGoalCard: some View {
        let weekTotal = habit.weeklyTotal()
        let prog      = min(Double(weekTotal) / Double(habit.weeklyGoal), 1.0)
        let done      = weekTotal >= habit.weeklyGoal

        return VStack(alignment: .leading, spacing: 10) {
            Label("Weekly Goal", systemImage: "calendar.badge.checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(accent)

            HStack {
                Text("\(weekTotal)")
                    .font(.cadNumber(36))
                    .foregroundColor(accent)
                Text("/ \(habit.weeklyGoal)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .alignmentGuide(.bottom) { $0[.bottom] }
                Spacer()
                if done {
                    Label("Complete!", systemImage: "star.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(theme.deep)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(done
                                      ? AnyShapeStyle(Color.green)
                                      : AnyShapeStyle(LinearGradient(colors: [accent.opacity(0.55), accent],
                                                                     startPoint: .leading, endPoint: .trailing)))
                        .frame(width: geo.size.width * prog)
                        .animation(.easeOut(duration: 0.4), value: prog)
                }
            }
            .frame(height: 8)

            Text("\(habit.weeklyGoal - min(weekTotal, habit.weeklyGoal)) more to go this week")
                .font(.caption).foregroundColor(.secondary)
                .opacity(done ? 0 : 1)
        }
        .padding()
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: accent.opacity(0.08), radius: 6, y: 2)
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $chartDays) {
                    Text("7d").tag(7)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }

            Chart(habit.countHistory(days: chartDays)) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Count", entry.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.6), accent],
                        startPoint: .bottom, endPoint: .top
                    )
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: chartDays <= 7 ? 1 : 7)) { _ in
                    AxisValueLabel(format: chartDays <= 7 ? .dateTime.weekday(.narrow) : .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Insights card

    private var weeklyMessages: [String] {
        var msgs: [String] = []
        let today      = habit.count()
        let weekTotal  = habit.weeklyTotal()
        let priorTotal = habit.priorWeeklyTotal()
        let streak     = habit.currentStreak

        if habit.type == .good {
            if streak > 0 && habit.streakState == .atRisk { msgs.append("\(streak)-day streak on the line — log it today to keep it.") }
            if streak >= 7                     { msgs.append("\(streak)-day streak — you're building a real routine.") }
            if priorTotal > 0 && weekTotal > priorTotal { msgs.append("Up from \(priorTotal) last week to \(weekTotal) this week — solid progress.") }
        } else {
            if today >= 3                      { msgs.append("Logged \(today) times today — pause before the next one.") }
            if priorTotal > 0 && weekTotal < priorTotal { msgs.append("Down from \(priorTotal) last week to \(weekTotal) this week — great work.") }
            if priorTotal > 0 && weekTotal > priorTotal { msgs.append("Up from \(priorTotal) last week — this trend is worth watching.") }
        }
        return msgs
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weekly Insights", systemImage: "chart.bar.xaxis.ascending")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(accent)
            ForEach(weeklyMessages, id: \.self) { msg in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(accent.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(msg).font(.subheadline).foregroundColor(.primary)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - AI analysis card

    private var aiAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Habit Coach", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(accent)

            if isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView().tint(accent)
                    Text("Analysing your week…").font(.subheadline).foregroundColor(.secondary)
                }
            } else if let analysis = aiAnalysis {
                Text(analysis).font(.subheadline).foregroundColor(.primary).fixedSize(horizontal: false, vertical: true)
                Button("Refresh") { runAnalysis() }.font(.caption.weight(.semibold)).foregroundColor(accent)
            } else if let error = analysisError {
                Text(error).font(.caption).foregroundColor(.red)
                Button("Retry") { runAnalysis() }.font(.caption.weight(.semibold)).foregroundColor(accent)
            } else {
                Text("Get a personalised insight based on your week's data.")
                    .font(.caption).foregroundColor(.secondary)
                Button("Generate insight") { runAnalysis() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Helpers

    private func runAnalysis() {
        isAnalyzing = true; analysisError = nil
        let service = AIService()
        let summary = habit.weekSummary()
        Task {
            do {
                let result = try await service.analyzeHabits([summary])
                await MainActor.run { aiAnalysis = result; isAnalyzing = false }
            } catch {
                await MainActor.run { analysisError = error.localizedDescription; isAnalyzing = false }
            }
        }
    }
}
