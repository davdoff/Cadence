import ActivityKit
import Foundation

// Member of BOTH the app target (which starts/ends the activity) and the
// CadenceWidget extension target (which renders it).

/// Drives the running-event countdown Live Activity (Lock Screen + Dynamic
/// Island). Started when the user taps Start; ended when the event is completed
/// or skipped. The countdown itself needs no updates — `Text(timerInterval:)`
/// renders it live from the `ContentState` window.
struct EventActivityAttributes: ActivityAttributes {
    /// The changing part: the timer window the countdown runs across.
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var finishAt: Date
    }

    /// Fixed for the life of the activity.
    var eventID: String
    var title: String
    var categoryColorHex: String?
}
