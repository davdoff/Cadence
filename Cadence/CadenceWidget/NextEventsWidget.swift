import WidgetKit
import SwiftUI

struct NextEventsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextEvents", provider: ScheduleProvider()) { entry in
            NextEventsWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Events")
        .description("Your next two events today.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct NextEventsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                rectangular
            } else {
                small
            }
        }
        .containerBackground(for: .widget) {
            family == .accessoryRectangular
                ? Color.clear
                : Color.appBackground(entry.accentHex)
        }
        .widgetURL(URL(string: "cadence://today"))
    }

    // MARK: - Small (home screen)

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            if entry.pending.isEmpty {
                Spacer()
                allDone
                Spacer()
            } else {
                ForEach(entry.pending.prefix(2)) { event in
                    eventRow(event)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ event: EventSnapshot) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(hex: event.colorHex))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(event.startTime, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var allDone: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(Color.appAccent(entry.accentHex))
            Text("All clear today")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rectangular (lock screen)

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let next = entry.pending.first {
                Text("Up next")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(next.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(next.startTime, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Cadence")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text("No more events today")
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
