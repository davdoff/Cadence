import ActivityKit
import Foundation

/// Starts and ends the running-event countdown Live Activity. App-target only —
/// `Activity.request` can't run in the widget process. No-ops gracefully when
/// Live Activities are disabled or unsupported, and never blocks starting the
/// event itself.
enum LiveActivityService {

    /// Begins the Lock Screen / Dynamic Island countdown for a just-started
    /// event. Call right after `event.startedAt` is set.
    static func start(for event: Event) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let startedAt = event.startedAt,
              let finishAt = event.finishTime else { return }

        let attributes = EventActivityAttributes(
            eventID: event.id.uuidString,
            title: event.title,
            categoryColorHex: event.category?.colorHex)
        let state = EventActivityAttributes.ContentState(startedAt: startedAt, finishAt: finishAt)

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: finishAt),
                pushType: nil)
        } catch {
            // A failed activity must not stop the event from starting.
        }
    }

    /// Removes any live activity for this event (completed or skipped).
    static func end(eventID: UUID) {
        Task {
            for activity in Activity<EventActivityAttributes>.activities
            where activity.attributes.eventID == eventID.uuidString {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
