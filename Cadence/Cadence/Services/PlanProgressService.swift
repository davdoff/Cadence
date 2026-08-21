import Foundation

/// Pure classification of a plan's scheduled sessions into review buckets — the
/// data the weekly-review card and the deterministic repair actions compute over.
/// No SwiftData / SwiftUI here (portable to Kotlin later, per CLAUDE.md): it takes
/// already-fetched `Event`s and a `now`, and returns value snapshots.
///
/// Accounting note: for *weekly re-planning*, a unit's work is "covered" by every
/// linked session that still exists (completed, upcoming, OR missed) — that's what
/// stops "Plan this week" from double-booking. Missed sessions are reclassified out
/// only by the review actions (Redo / Skip / Drop), never automatically.
enum PlanProgressService {

    /// Where a single scheduled session sits relative to `now`.
    enum Bucket {
        case upcoming    // pending and not yet ended
        case completed   // marked done
        case missed      // marked missed, or pending but already ended (needs review)
    }

    static func bucket(for event: Event, now: Date = .now) -> Bucket {
        switch event.status {
        case .completed: return .completed
        case .missed, .displaced: return .missed
        case .pending: return event.endTime < now ? .missed : .upcoming
        }
    }

    /// A plan's sessions split by bucket, each list sorted soonest-first.
    struct Snapshot {
        let upcoming: [Event]
        let completed: [Event]
        let missed: [Event]

        var isEmpty: Bool { upcoming.isEmpty && completed.isEmpty && missed.isEmpty }
        var needsReview: Bool { !missed.isEmpty }
        var completedCount: Int { completed.count }
        var upcomingCount: Int { upcoming.count }
        var missedCount: Int { missed.count }
    }

    /// Classify every session linked to `planID`.
    static func snapshot(planID: UUID, events: [Event], now: Date = .now) -> Snapshot {
        let linked = events.filter { $0.planID == planID }
        var upcoming: [Event] = [], completed: [Event] = [], missed: [Event] = []
        for e in linked {
            switch bucket(for: e, now: now) {
            case .upcoming: upcoming.append(e)
            case .completed: completed.append(e)
            case .missed: missed.append(e)
            }
        }
        let bySoonest: (Event, Event) -> Bool = { $0.startTime < $1.startTime }
        return Snapshot(
            upcoming: upcoming.sorted(by: bySoonest),
            completed: completed.sorted(by: bySoonest),
            missed: missed.sorted(by: bySoonest)
        )
    }
}
