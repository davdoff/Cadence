import WidgetKit
import SwiftUI

// Standalone Quick Timer feature — see CADENCE_WIDGET_TIMERS.md.
// Not wired to Event/Habit/Meal data; safe to delete independently.

struct QuickTimerEntry: TimelineEntry {
    let date: Date
    let slots: [TimeInterval]
    let endDate: Date?
    let accentHex: String
}

struct QuickTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickTimerEntry {
        QuickTimerEntry(date: .now, slots: TimerSettingsStore.defaultSlotsSeconds, endDate: nil, accentHex: WidgetTheme.accentHex)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickTimerEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickTimerEntry>) -> Void) {
        let current = entry()
        // While idle there's nothing to react to; once running, refresh right as
        // the countdown ends so the widget flips back to the idle/preset view.
        let refreshDate = current.endDate ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [current], policy: .after(refreshDate)))
    }

    private func entry() -> QuickTimerEntry {
        QuickTimerEntry(
            date: .now,
            slots: TimerSettingsStore.slotsSeconds(),
            endDate: TimerSettingsStore.isRunning ? TimerSettingsStore.endDate : nil,
            accentHex: WidgetTheme.accentHex
        )
    }
}

struct QuickTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickTimer", provider: QuickTimerProvider()) { entry in
            QuickTimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Timer")
        .description("Tap a preset to start a countdown. Edit presets in Settings > Quick Timer.")
        .supportedFamilies([.systemMedium])
    }
}

struct QuickTimerWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: QuickTimerEntry

    var body: some View {
        Group {
            if let end = entry.endDate, end > entry.date {
                runningView(end: end)
            } else {
                idleView
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.background(accentHex: entry.accentHex, dark: colorScheme == .dark)
        }
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Timer")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(entry.slots.enumerated()), id: \.offset) { _, seconds in
                    Button(intent: StartQuickTimerIntent(seconds: seconds)) {
                        Text(TimerSettingsStore.durationLabel(seconds, compact: true))
                            .font(.caption2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.appAccent(entry.accentHex).opacity(0.15))
                            .foregroundColor(Color.appAccent(entry.accentHex))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private func runningView(end: Date) -> some View {
        // The range must be built from the entry's frozen date, never `Date.now`:
        // WidgetKit can render this entry after `end` has passed, and an inverted
        // `ClosedRange` traps at runtime — crashing the whole widget.
        VStack(spacing: 8) {
            Text(timerInterval: entry.date...end, countsDown: true)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Color.appAccent(entry.accentHex))
            Button(intent: CancelQuickTimerIntent()) {
                Text("Cancel")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
