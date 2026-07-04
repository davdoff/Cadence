import WidgetKit
import SwiftUI

struct MealEntry: TimelineEntry {
    let date: Date
    let meal: EventSnapshot?
    let accentHex: String
}

struct NextMealProvider: TimelineProvider {

    func placeholder(in context: Context) -> MealEntry {
        MealEntry(
            date: .now,
            meal: EventSnapshot(id: UUID(), title: "Carbonara", startTime: Date().addingTimeInterval(7200),
                                endTime: Date().addingTimeInterval(10800), colorHex: "#F0AD4E"),
            accentHex: WidgetTheme.accentHex
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MealEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
        let now = Date()
        let entry = entry(at: now)
        let midnight = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
        )!
        // Refresh when the shown meal starts (so the following one takes over), else at midnight.
        let reload = entry.meal.map { min($0.startTime, midnight) } ?? midnight
        completion(Timeline(entries: [entry], policy: .after(reload)))
    }

    private func entry(at date: Date) -> MealEntry {
        MealEntry(date: date, meal: WidgetDataStore.nextMeal(now: date), accentHex: WidgetTheme.accentHex)
    }
}

struct NextMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextMeal", provider: NextMealProvider()) { entry in
            NextMealWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Meal")
        .description("Your upcoming meal and its time.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextMealWidgetView: View {
    let entry: MealEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(hex: entry.meal?.colorHex ?? entry.accentHex))
                    .clipShape(Circle())
                Spacer()
            }

            Spacer(minLength: 0)

            if let meal = entry.meal {
                Text(meal.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(meal.startTime, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No meal planned")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Plan one in Cadence")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color.appBackground(entry.accentHex)
        }
        .widgetURL(URL(string: "cadence://meals"))
    }
}
