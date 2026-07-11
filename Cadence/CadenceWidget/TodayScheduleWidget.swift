import WidgetKit
import SwiftUI

struct TodayScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySchedule", provider: ScheduleProvider()) { entry in
            TodayScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Schedule")
        .description("Today's progress and your next three events.")
        .supportedFamilies([.systemMedium])
    }
}

struct TodayScheduleWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: ScheduleEntry

    private var progress: Double {
        entry.total == 0 ? 0 : Double(entry.completed) / Double(entry.total)
    }

    var body: some View {
        HStack(spacing: 14) {
            dayColumn
            Divider()
                .overlay(Color.appDeep(entry.accentHex))
            eventsColumn
        }
        .containerBackground(for: .widget) {
            WidgetTheme.background(accentHex: entry.accentHex, dark: colorScheme == .dark)
        }
        .widgetURL(URL(string: "cadence://today"))
    }

    // MARK: - Left column

    private var dayColumn: some View {
        VStack(spacing: 8) {
            Text(entry.date.formatted(.dateTime.weekday(.wide)))
                .font(.subheadline.weight(.semibold))
            ZStack {
                ProgressRing(
                    progress: progress,
                    color: Color.appAccent(entry.accentHex),
                    lineWidth: 6
                )
                Text("\(entry.completed)/\(entry.total)")
                    .font(.callout.weight(.bold))
                    .foregroundColor(Color.appAccent(entry.accentHex))
            }
            .frame(width: 54, height: 54)
            Text("completed")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 90)
    }

    // MARK: - Right column

    private var eventsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.pending.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(Color.appAccent(entry.accentHex))
                        Text("All clear for today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.pending.prefix(3)) { event in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: event.colorHex))
                            .frame(width: 8, height: 8)
                        Text(event.startTime, style: .time)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text(event.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
