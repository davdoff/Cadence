import ActivityKit
import WidgetKit
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit

// Standalone Quick Timer feature — see CADENCE_WIDGET_TIMERS.md.
//
// AlarmKit *requires* a widget extension whenever an alarm uses a countdown
// presentation — without one "the system may unexpectedly dismiss alarms and
// fail to alert." This is that extension: it renders the non-alerting states
// (Lock Screen, Dynamic Island, StandBy). The alerting UI itself is drawn by
// the system from the AlarmPresentation.Alert we supplied.

/// Lock Screen banner + Dynamic Island for a running Quick Timer alarm.
/// Layout mirrors `EventLiveActivity`, driven by AlarmKit's own attributes.
@available(iOS 26.0, *)
struct QuickTimerAlarmActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<QuickTimerMetadata>.self) { context in
            lockScreen(context)
                .activityBackgroundTint(WidgetTheme.darkSurface.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("Quick Timer").font(.headline).lineLimit(1)
                    } icon: {
                        Image(systemName: "timer").foregroundStyle(tint(context))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusText(context)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(tint(context))
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(tint(context))
            } compactTrailing: {
                statusText(context)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 44)
                    .foregroundStyle(tint(context))
            } minimal: {
                Image(systemName: "timer").foregroundStyle(tint(context))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<AlarmAttributes<QuickTimerMetadata>>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(tint(context))
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Timer")
                    .font(.headline)
                    .lineLimit(1)
                statusText(context)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(tint(context))
            }
            Spacer()
        }
        .padding()
    }

    /// The live countdown, or a done/paused label. `.countdown` carries the fire
    /// date, so `Text(timerInterval:)` keeps ticking without timeline reloads.
    private func statusText(_ context: ActivityViewContext<AlarmAttributes<QuickTimerMetadata>>) -> Text {
        switch context.state.mode {
        case .countdown(let fireDate):
            // Guard the range: an entry rendered after the fire date would
            // otherwise build an inverted ClosedRange and trap.
            let now = Date.now
            return fireDate > now
                ? Text(timerInterval: now...fireDate, countsDown: true)
                : Text("Timer done")
        case .paused:
            return Text("Paused")
        case .alerting:
            return Text("Timer done")
        @unknown default:
            return Text("Quick Timer")
        }
    }

    private func tint(_ context: ActivityViewContext<AlarmAttributes<QuickTimerMetadata>>) -> Color {
        context.attributes.tintColor
    }
}

#endif
