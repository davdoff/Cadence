import WidgetKit
import SwiftUI

struct HabitEntry: TimelineEntry {
    let date: Date
    let habit: HabitSnapshot?
    let accentHex: String
}

extension HabitSnapshot {
    static var sample: HabitSnapshot {
        HabitSnapshot(id: UUID(), name: "Read", symbolName: "book.fill", colorHex: "#5278E0",
                      todayCount: 2, dailyGoal: 3, weekCount: 12, weeklyGoal: 20)
    }
}

struct HabitProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: .now, habit: .sample, accentHex: WidgetTheme.accentHex)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> HabitEntry {
        context.isPreview ? placeholder(in: context) : entry(for: configuration)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<HabitEntry> {
        let midnight = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)
        )!
        // Counts only change via the app (which reloads timelines) or the
        // increment intent — the timer only needs to roll the day over.
        return Timeline(entries: [entry(for: configuration)], policy: .after(midnight))
    }

    private func entry(for configuration: SelectHabitIntent) -> HabitEntry {
        let habit = configuration.habit.flatMap { WidgetDataStore.habit(id: $0.id) }
            ?? WidgetDataStore.allHabits().first
        return HabitEntry(date: .now, habit: habit, accentHex: WidgetTheme.accentHex)
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Habit", intent: SelectHabitIntent.self, provider: HabitProvider()) { entry in
            HabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Habit Goal")
        .description("Daily and weekly progress for one habit — log it right from the widget.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: HabitEntry

    var body: some View {
        Group {
            if let habit = entry.habit {
                if family == .accessoryCircular {
                    circular(habit)
                } else {
                    small(habit)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            family == .accessoryCircular
                ? Color.clear
                : WidgetTheme.background(accentHex: entry.accentHex, dark: colorScheme == .dark)
        }
        .widgetURL(URL(string: "cadence://habits"))
    }

    // MARK: - Small (home screen)

    private func small(_ habit: HabitSnapshot) -> some View {
        let color = Color(hex: habit.colorHex)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: habit.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(Circle())
                Spacer(minLength: 0)
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(weeklyLine(habit))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                ZStack {
                    ProgressRing(progress: dailyProgress(habit), color: color, lineWidth: 5)
                    Text("\(habit.todayCount)")
                        .font(.callout.weight(.bold))
                        .foregroundColor(color)
                }
                .frame(width: 44, height: 44)
                Spacer(minLength: 0)
                Button(intent: IncrementHabitIntent(habitID: habit.id)) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(color)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Circular (lock screen)

    private func circular(_ habit: HabitSnapshot) -> some View {
        Gauge(value: Double(min(habit.todayCount, max(habit.dailyGoal, 1))),
              in: 0...Double(max(habit.dailyGoal, 1))) {
            Image(systemName: habit.symbolName)
        } currentValueLabel: {
            Text("\(habit.todayCount)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.heart.fill")
                .font(.title3)
                .foregroundColor(Color.appAccent(entry.accentHex))
            Text("Add a habit in Cadence")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func dailyProgress(_ habit: HabitSnapshot) -> Double {
        habit.dailyGoal == 0 ? 0 : Double(habit.todayCount) / Double(habit.dailyGoal)
    }

    private func weeklyLine(_ habit: HabitSnapshot) -> String {
        habit.weeklyGoal > 0
            ? "\(habit.weekCount)/\(habit.weeklyGoal) this week"
            : "\(habit.weekCount) this week"
    }
}
