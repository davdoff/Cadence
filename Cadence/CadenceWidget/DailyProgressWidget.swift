import WidgetKit
import SwiftUI

struct DailyProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyProgress", provider: ScheduleProvider()) { entry in
            DailyProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Progress")
        .description("Completed vs total events today.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct DailyProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: ScheduleEntry

    private var progress: Double {
        entry.total == 0 ? 0 : Double(entry.completed) / Double(entry.total)
    }

    var body: some View {
        Group {
            if family == .accessoryCircular {
                circular
            } else {
                small
            }
        }
        .containerBackground(for: .widget) {
            family == .accessoryCircular
                ? Color.clear
                : WidgetTheme.background(accentHex: entry.accentHex, dark: colorScheme == .dark)
        }
        .widgetURL(URL(string: "cadence://today"))
    }

    // MARK: - Small (home screen)

    private var small: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(
                    progress: progress,
                    color: Color.appAccent(entry.accentHex),
                    lineWidth: 7
                )
                Text("\(entry.completed)/\(entry.total)")
                    .font(.title3.weight(.bold))
                    .foregroundColor(Color.appAccent(entry.accentHex))
            }
            .frame(width: 72, height: 72)

            Text("completed today")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Circular (lock screen)

    private var circular: some View {
        Gauge(value: Double(entry.completed), in: 0...Double(max(entry.total, 1))) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(entry.completed)/\(entry.total)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}
