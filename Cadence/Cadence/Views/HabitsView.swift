import SwiftUI
import SwiftData

// MARK: - HabitsView

struct HabitsView: View {
    @Environment(\.theme) private var theme
    @Query private var habits: [Habit]
    @Environment(\.modelContext) private var context

    @State private var showingAddHabit = false
    @State private var selectedHabit: Habit?
    @State private var editingHabit: Habit?
    @State private var habitToDelete: Habit?
    @State private var filter: HabitFilter = .all
    @State private var sort: HabitSort = .streak
    @AppStorage("habitCompact") private var compact = false

    enum HabitFilter: String, CaseIterable {
        case all = "All", good = "Good", bad = "Bad"
    }
    enum HabitSort: String, CaseIterable {
        case streak = "Streak", today = "Today", name = "A–Z"
        var icon: String {
            switch self { case .streak: "flame.fill"; case .today: "plus.circle.fill"; case .name: "textformat" }
        }
    }

    private var goodHabits: [Habit] { habits.filter { $0.type == .good } }
    private var badHabits:  [Habit] { habits.filter { $0.type == .bad  } }

    private func sorted(_ list: [Habit]) -> [Habit] {
        switch sort {
        case .streak: return list.sorted { $0.currentStreak > $1.currentStreak }
        case .today:  return list.sorted { $0.count() > $1.count() }
        case .name:   return list.sorted { $0.name < $1.name }
        }
    }

    private var visibleGood: [Habit] { filter == .bad  ? [] : sorted(goodHabits) }
    private var visibleBad:  [Habit] { filter == .good ? [] : sorted(badHabits)  }

    private var totalGoodToday: Int { goodHabits.reduce(0) { $0 + $1.count()              } }
    private var totalGoodGoal:  Int { goodHabits.reduce(0) { $0 + max($1.dailyGoal, 1)   } }
    private var totalBadToday:  Int { badHabits.reduce(0)  { $0 + $1.count()              } }
    private var overallRate:  Double {
        totalGoodGoal > 0 ? min(Double(totalGoodToday) / Double(totalGoodGoal), 1.0) : 0
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            if habits.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        controlRow
                        if !visibleGood.isEmpty { habitSection(label: "Good Habits", list: visibleGood) }
                        if !visibleBad.isEmpty  { habitSection(label: "Bad Habits",  list: visibleBad)  }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.spring(duration: 0.25)) { compact.toggle() }
                } label: {
                    Image(systemName: compact ? "rectangle.grid.1x2.fill" : "square.grid.2x2.fill")
                        .foregroundColor(theme.accent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddHabit = true } label: {
                    Image(systemName: "plus").foregroundColor(theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingAddHabit) { AddHabitView() }
        .sheet(item: $editingHabit) { AddHabitView(editingHabit: $0) }
        .navigationDestination(item: $selectedHabit) { HabitDetailView(habit: $0) }
        .alert(
            "Delete \(habitToDelete?.name ?? "habit")?",
            isPresented: Binding(
                get: { habitToDelete != nil },
                set: { if !$0 { habitToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let habit = habitToDelete {
                    context.delete(habit)
                    try? context.save()
                    WidgetSync.refresh()
                }
                habitToDelete = nil
            }
            Button("Cancel", role: .cancel) { habitToDelete = nil }
        } message: {
            Text("This permanently deletes the habit and its full history.")
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                ZStack {
                    // Conic accent ring with a punched (unfilled) center — §4.
                    Circle()
                        .stroke(theme.track, lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: overallRate)
                        .stroke(
                            theme.ringGradient,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: overallRate)
                    Text("\(Int(overallRate * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.accent)
                }
                .frame(width: 64, height: 64)
                Text("Daily goal").font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(theme.deep).frame(width: 1, height: 52)

            VStack(spacing: 4) {
                Text("\(totalGoodToday)")
                    .font(.cadNumber(32))
                    .foregroundColor(theme.accent)
                    .contentTransition(.numericText())
                Text("good logged").font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(theme.deep).frame(width: 1, height: 52)

            VStack(spacing: 4) {
                Text("\(totalBadToday)")
                    .font(.cadNumber(32))
                    .foregroundColor(totalBadToday > 0 ? .red.opacity(0.8) : .secondary)
                    .contentTransition(.numericText())
                Text("bad tracked").font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 18)
        .cardStyle(prominent: true)
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: 10) {
            // Filter picker
            HStack(spacing: 0) {
                ForEach(HabitFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(.spring(duration: 0.2)) { filter = f }
                    } label: {
                        Text(f.rawValue)
                            .font(.cadFootnote)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(filter == f ? AnyShapeStyle(theme.pillGradient) : AnyShapeStyle(Color.clear))
                            .foregroundColor(filter == f ? .white : theme.chipText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(theme.chipBg)
            .clipShape(Capsule())

            Spacer()

            // Sort picker
            Menu {
                ForEach(HabitSort.allCases, id: \.self) { s in
                    Button {
                        withAnimation { sort = s }
                    } label: {
                        Label(s.rawValue, systemImage: s.icon)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: sort.icon).font(.caption)
                    Text(sort.rawValue).font(.cadFootnote)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(theme.chipBg)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Section

    private func habitSection(label: String, list: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            ForEach(list) { habit in
                HabitCard(habit: habit, compact: compact) { selectedHabit = habit }
                    .contextMenu {
                        Button { selectedHabit = habit } label: { Label("View Details", systemImage: "chart.bar.fill") }
                        Button { editingHabit = habit } label: { Label("Edit", systemImage: "pencil") }
                        Divider()
                        // Confirmed below — one stray tap must not destroy
                        // the habit's full history (UI_REVIEW §2).
                        Button(role: .destructive) {
                            habitToDelete = habit
                        } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(theme.emptyOrb)
                    .frame(width: 90, height: 90)
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 40))
                    .foregroundColor(theme.accent)
            }
            Text("No habits yet")
                .font(.cadHeadline).foregroundColor(.secondary)
            Text("Start tracking what you want to build — and what you want to break.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button { showingAddHabit = true } label: {
                Label("Add your first habit", systemImage: "plus")
                    .font(.cadFootnote)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(theme.pillGradient)
                    .clipShape(Capsule())
                    .shadow(color: theme.pillGlow, radius: 10, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - HabitCard

struct HabitCard: View {
    @Environment(\.theme) private var theme
    let habit: Habit
    let compact: Bool
    let onDetail: () -> Void
    @Environment(\.modelContext) private var context

    /// Per-habit tile palette (CADENCE_DESIGN_SYSTEM §4/§5), resolved for the
    /// active surface. `accent` is its icon color — the single flat hue used by
    /// streaks, counts, and shadows.
    private var tile:        HabitTileColor.Tokens { HabitTileColor.by(id: habit.tileColorID).tokens(dark: theme.isDark) }
    private var accent:      Color { tile.icon }
    private var todayCount:  Int   { habit.count() }
    private var dailyProg:   Double {
        guard habit.type == .good, habit.dailyGoal > 0 else { return 0 }
        return min(Double(todayCount) / Double(habit.dailyGoal), 1.0)
    }
    private var weeklyProg: Double {
        guard habit.weeklyGoal > 0 else { return 0 }
        return min(Double(habit.weeklyTotal()) / Double(habit.weeklyGoal), 1.0)
    }
    private var dailyDone:  Bool { habit.type == .good && habit.dailyGoal > 0 && todayCount >= habit.dailyGoal }
    private var weeklyDone: Bool { habit.weeklyGoal > 0 && habit.weeklyTotal() >= habit.weeklyGoal }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 10) {
            topRow
            if !compact {
                if habit.type == .good && habit.dailyGoal > 0 { dailyBar }
                if habit.weeklyGoal > 0 { weeklyBar }
            }
        }
        .padding(compact ? 10 : 14)
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: accent.opacity(0.08), radius: 5, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(dailyDone ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 10 : 12)
                    .fill(tile.tileGradient)
                Image(systemName: habit.symbolName)
                    .font(.system(size: compact ? 16 : 20, weight: .semibold))
                    .foregroundColor(tile.icon)
            }
            .frame(width: compact ? 36 : 46, height: compact ? 36 : 46)

            // Name + streak
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(compact ? .subheadline : .subheadline.weight(.semibold))
                    .lineLimit(1)
                if !compact {
                    if habit.type == .good {
                        let s = habit.currentStreak
                        Label(
                            s > 0 ? "\(s) day streak" : "Start your streak today",
                            systemImage: s > 0 ? "flame.fill" : "flame"
                        )
                        .font(.caption)
                        .foregroundColor(s > 0 ? accent : .secondary)
                    } else {
                        Text("This week: \(habit.weeklyTotal())")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Quick-log controls
            HStack(spacing: compact ? 6 : 8) {
                Button {
                    withAnimation(.spring(duration: 0.2)) { habit.decrement(); try? context.save() }
                    WidgetSync.refresh()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: compact ? 24 : 28))
                        .foregroundColor(Color.gray.opacity(0.3))
                }
                .buttonStyle(.plain)

                Text("\(todayCount)")
                    .font(compact ? .subheadline.weight(.bold) : .title3.weight(.bold))
                    .foregroundColor(accent)
                    .frame(minWidth: 20, alignment: .center)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: todayCount)

                Button {
                    withAnimation(.spring(duration: 0.2)) { habit.increment(); try? context.save() }
                    WidgetSync.refresh()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: compact ? 24 : 28))
                        .foregroundStyle(tile.buttonGradient)
                }
                .buttonStyle(.plain)
            }

            // Detail chevron
            Button(action: onDetail) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color.gray.opacity(0.35))
                    .padding(.leading, 2)
            }
            .buttonStyle(.plain)
        }
    }

    // Daily progress bar
    private var dailyBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.deep)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dailyDone
                              ? AnyShapeStyle(Color.green)
                              : AnyShapeStyle(tile.buttonGradient))
                        .frame(width: geo.size.width * dailyProg)
                        .animation(.easeOut(duration: 0.3), value: dailyProg)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(todayCount) / \(habit.dailyGoal) today")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                if dailyDone {
                    Label("Daily goal!", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold)).foregroundColor(.green)
                }
            }
        }
    }

    // Weekly progress bar
    private var weeklyBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.deep)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(weeklyDone
                              ? AnyShapeStyle(Color.green)
                              : AnyShapeStyle(tile.buttonGradient))
                        .opacity(weeklyDone ? 1 : 0.7)
                        .frame(width: geo.size.width * weeklyProg)
                        .animation(.easeOut(duration: 0.3), value: weeklyProg)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(habit.weeklyTotal()) / \(habit.weeklyGoal) this week")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                if weeklyDone {
                    Label("Weekly goal!", systemImage: "star.circle.fill")
                        .font(.caption2.weight(.semibold)).foregroundColor(.green)
                }
            }
        }
    }
}
