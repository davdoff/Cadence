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
    @Environment(\.colorScheme) private var colorScheme
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
                : WidgetTheme.background(accentHex: entry.accentHex, dark: colorScheme == .dark)
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
                // Locations only when both rows still fit with them.
                ViewThatFits(in: .vertical) {
                    eventRows(showLocation: true)
                    eventRows(showLocation: false)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRows(showLocation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.pending.prefix(2)) { event in
                eventRow(event, showLocation: showLocation)
            }
        }
    }

    private func eventRow(_ event: EventSnapshot, showLocation: Bool) -> some View {
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
                if showLocation, let location = event.location {
                    Text(location)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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
                timeAndLocation(next)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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

    /// "09:00 · Room 2A-04, Main Building" — one line; the location end
    /// truncates first since the time comes first.
    private func timeAndLocation(_ event: EventSnapshot) -> Text {
        let time = Text(event.startTime, style: .time)
        guard let location = event.location else { return time }
        return Text("\(time) · \(location)")
    }
}
