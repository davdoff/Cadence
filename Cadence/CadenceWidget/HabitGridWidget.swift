import WidgetKit
import SwiftUI

struct HabitGridEntry: TimelineEntry {
    let date: Date
    let habits: [HabitSnapshot]
    let accentHex: String
}

struct HabitGridProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> HabitGridEntry {
        HabitGridEntry(
            date: .now,
            habits: [
                .sample,
                HabitSnapshot(id: UUID(), name: "Water", symbolName: "drop.fill", colorHex: "#52B4E0",
                              todayCount: 5, dailyGoal: 8, weekCount: 40, weeklyGoal: 0),
                HabitSnapshot(id: UUID(), name: "Run", symbolName: "figure.run", colorHex: "#52C47A",
                              todayCount: 1, dailyGoal: 1, weekCount: 4, weeklyGoal: 5),
                HabitSnapshot(id: UUID(), name: "Journal", symbolName: "pencil", colorHex: "#E0A052",
                              todayCount: 0, dailyGoal: 1, weekCount: 3, weeklyGoal: 7)
            ],
            accentHex: WidgetTheme.accentHex
        )
    }

    func snapshot(for configuration: SelectHabitsIntent, in context: Context) async -> HabitGridEntry {
        context.isPreview ? placeholder(in: context) : entry(for: configuration)
    }

    func timeline(for configuration: SelectHabitsIntent, in context: Context) async -> Timeline<HabitGridEntry> {
        let midnight = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)
        )!
        return Timeline(entries: [entry(for: configuration)], policy: .after(midnight))
    }

    private func entry(for configuration: SelectHabitsIntent) -> HabitGridEntry {
        let habits: [HabitSnapshot]
        if let chosen = configuration.habits, !chosen.isEmpty {
            habits = chosen.compactMap { WidgetDataStore.habit(id: $0.id) }
        } else {
            habits = Array(WidgetDataStore.allHabits().prefix(4))
        }
        return HabitGridEntry(date: .now, habits: Array(habits.prefix(4)), accentHex: WidgetTheme.accentHex)
    }
}

struct HabitGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HabitGrid", intent: SelectHabitsIntent.self, provider: HabitGridProvider()) { entry in
            HabitGridWidgetView(entry: entry)
        }
        .configurationDisplayName("Habit Grid")
        .description("Up to four habits at a glance, each with its own log button.")
        .supportedFamilies([.systemSmall])
    }
}

struct HabitGridWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: HabitGridEntry

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        Group {
            if entry.habits.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(entry.habits) { habit in
                        cell(habit)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.background(accentHex: entry.accentHex, dark: colorScheme == .dark)
        }
        .widgetURL(URL(string: "cadence://habits"))
    }

    private func cell(_ habit: HabitSnapshot) -> some View {
        let color = Color(hex: habit.colorHex)
        let progress = habit.dailyGoal == 0 ? 0 : Double(habit.todayCount) / Double(habit.dailyGoal)
        return VStack(spacing: 3) {
            ZStack {
                ProgressRing(progress: progress, color: color, lineWidth: 3.5)
                Image(systemName: habit.symbolName)
                    .font(.caption2)
                    .foregroundColor(color)
            }
            .frame(width: 32, height: 32)
            HStack(spacing: 3) {
                Text(habit.dailyGoal > 0 ? "\(habit.todayCount)/\(habit.dailyGoal)" : "\(habit.todayCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(color)
                Button(intent: IncrementHabitIntent(habitID: habit.id)) {
                    Image(systemName: "plus.circle.fill")
                        .font(.footnote)
                        .foregroundColor(color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.heart.fill")
                .font(.title3)
                .foregroundColor(Color.appAccent(entry.accentHex))
            Text("Add habits in Cadence")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
