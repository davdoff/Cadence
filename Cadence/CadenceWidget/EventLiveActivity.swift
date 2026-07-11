import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen banner + Dynamic Island for a running event's countdown.
/// Driven by `EventActivityAttributes`; the timer text is self-updating.
struct EventLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(WidgetTheme.darkSurface.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                    } icon: {
                        Image(systemName: "timer").foregroundStyle(accent(context))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(context)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(accent(context))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(timerInterval: context.state.startedAt...context.state.finishAt,
                                     countsDown: false)
                            .tint(accent(context))
                        stopButton(context)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(accent(context))
            } compactTrailing: {
                timerText(context)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 44)
                    .foregroundStyle(accent(context))
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent(context))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<EventActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(accent(context))
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("In progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                timerText(context)
                    .font(.title.monospacedDigit())
                    .foregroundStyle(accent(context))
                stopButton(context)
            }
        }
        .padding()
    }

    /// Interactive Stop button. Runs `StopEventIntent` in the app process,
    /// which completes the event and ends the activity. Shown on the Lock
    /// Screen and the expanded island (compact/minimal can't host buttons).
    private func stopButton(_ context: ActivityViewContext<EventActivityAttributes>) -> some View {
        Button(intent: StopEventIntent(eventID: context.attributes.eventID)) {
            Label("Stop", systemImage: "stop.fill")
                .font(.caption.weight(.semibold))
        }
        .tint(accent(context))
        .buttonStyle(.bordered)
    }

    private func timerText(_ context: ActivityViewContext<EventActivityAttributes>) -> Text {
        Text(timerInterval: context.state.startedAt...context.state.finishAt, countsDown: true)
    }

    private func accent(_ context: ActivityViewContext<EventActivityAttributes>) -> Color {
        if let hex = context.attributes.categoryColorHex { return Color(hex: hex) }
        return Color(hex: WidgetTheme.accentHex)
    }
}
