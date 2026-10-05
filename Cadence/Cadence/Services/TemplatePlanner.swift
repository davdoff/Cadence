import Foundation

/// Lays a day template onto a concrete date against the events already there
/// (day-templates.md). Pure: values in, values out, no ModelContext — this is
/// the decision logic that gets hand-ported to Kotlin, so keep it out of views.
///
/// Rules:
/// - A block whose template time is free keeps it.
/// - A block that clashes slides to the nearest free gap the same day (ties go
///   later, so blocks keep their order). The user's existing events stay put…
/// - …unless the user flips "move my event instead" for a clashing event
///   (`moveExisting`): then the block keeps its template time and that event is
///   re-placed at the nearest free gap to where it was.
/// - The buffer applies between template blocks and existing events, and
///   between existing events — but not between two template blocks: the
///   template is the user's own layout, back-to-back blocks are intentional.
/// - The search window is the whole day (not work hours — templates often hold
///   an evening gym block or a morning routine), never earlier than `notBefore`.
///   Avoid-blocks are ignored for the same reason.
/// - Nothing is dropped silently: a block with no room is `.unplaceable`, and an
///   event that can't be moved stays where it is and is reported in `unmovable`.
enum TemplatePlanner {

    struct ExistingItem: Equatable {
        let id: UUID
        let title: String
        let start: Date
        let end: Date
        var isRecurring: Bool = false
        var isImported: Bool = false
    }

    enum BlockOutcome: Equatable {
        case asIs
        case shifted(from: Date)
        case unplaceable
    }

    struct PlannedBlock: Equatable {
        let block: TemplateBlock
        let start: Date
        let end: Date
        let outcome: BlockOutcome
        /// Existing events overlapping the block's *template* time (buffer
        /// included), whether or not they are being moved — the UI offers a
        /// "move this instead" toggle for each.
        let clashesWith: [UUID]
    }

    struct ExistingMove: Equatable {
        let eventID: UUID
        let newStart: Date
        let newEnd: Date
    }

    struct DayPlan: Equatable {
        let day: Date
        let blocks: [PlannedBlock]
        let moves: [ExistingMove]
        /// Requested moves that found no free gap; those events stay put.
        let unmovable: Set<UUID>

        var placedBlocks: [PlannedBlock] { blocks.filter { $0.outcome != .unplaceable } }
    }

    // MARK: - Planning

    static func plan(
        template: [TemplateBlock],
        on day: Date,
        existing: [ExistingItem],
        moveExisting: Set<UUID> = [],
        bufferMinutes: Int,
        notBefore: Date? = nil,
        calendar: Calendar = .current
    ) -> DayPlan {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let windowStart = max(dayStart, notBefore ?? dayStart)
        let window = (start: windowStart, end: dayEnd)
        let buffer = TimeInterval(bufferMinutes * 60)

        var unmovable = Set<UUID>()
        var toMove = moveExisting
        // Each pass either succeeds or removes the event(s) that found no room,
        // so this runs at most moveExisting.count + 1 times.
        while true {
            var occupied: [Occupied] = existing
                .filter { !toMove.contains($0.id) }
                .map { Occupied(start: $0.start, end: $0.end, isTemplate: false) }

            var planned: [PlannedBlock] = []
            for block in template.sorted(by: { $0.startMinuteOfDay < $1.startMinuteOfDay }) {
                let start = dayStart.addingTimeInterval(TimeInterval(block.startMinuteOfDay * 60))
                let duration = TimeInterval(block.durationMinutes * 60)
                let end = start.addingTimeInterval(duration)
                let clashes = existing
                    .filter { $0.start < end + buffer && $0.end > start - buffer }
                    .map(\.id)

                if fits(start: start, end: end, isTemplate: true, occupied: occupied, buffer: buffer, window: window) {
                    planned.append(PlannedBlock(block: block, start: start, end: end, outcome: .asIs, clashesWith: clashes))
                    occupied.append(Occupied(start: start, end: end, isTemplate: true))
                } else if let newStart = nearestGap(duration: duration, preferred: start, isTemplate: true,
                                                    occupied: occupied, buffer: buffer, window: window) {
                    let newEnd = newStart.addingTimeInterval(duration)
                    planned.append(PlannedBlock(block: block, start: newStart, end: newEnd,
                                                outcome: .shifted(from: start), clashesWith: clashes))
                    occupied.append(Occupied(start: newStart, end: newEnd, isTemplate: true))
                } else {
                    planned.append(PlannedBlock(block: block, start: start, end: end,
                                                outcome: .unplaceable, clashesWith: clashes))
                }
            }

            var moves: [ExistingMove] = []
            var failed = Set<UUID>()
            for item in existing.filter({ toMove.contains($0.id) }).sorted(by: { $0.start < $1.start }) {
                let duration = item.end.timeIntervalSince(item.start)
                if let newStart = nearestGap(duration: duration, preferred: item.start, isTemplate: false,
                                             occupied: occupied, buffer: buffer, window: window) {
                    let newEnd = newStart.addingTimeInterval(duration)
                    moves.append(ExistingMove(eventID: item.id, newStart: newStart, newEnd: newEnd))
                    occupied.append(Occupied(start: newStart, end: newEnd, isTemplate: false))
                } else {
                    failed.insert(item.id)
                }
            }

            if failed.isEmpty {
                return DayPlan(day: dayStart, blocks: planned, moves: moves, unmovable: unmovable)
            }
            // An event with nowhere to go stays where it was; re-plan around it.
            unmovable.formUnion(failed)
            toMove.subtract(failed)
        }
    }

    /// One `DayPlan` per day, in date order. `assignments` maps a day (any time
    /// on it) to the blocks of the template chosen for it; `existing` may span
    /// the whole period — each day only sees the events that overlap it.
    static func planPeriod(
        assignments: [(day: Date, blocks: [TemplateBlock])],
        existing: [ExistingItem],
        moveExisting: Set<UUID> = [],
        bufferMinutes: Int,
        notBefore: Date? = nil,
        calendar: Calendar = .current
    ) -> [DayPlan] {
        assignments
            .sorted { $0.day < $1.day }
            .map { entry in
                let dayStart = calendar.startOfDay(for: entry.day)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let sameDay = existing.filter { $0.start < dayEnd && $0.end > dayStart }
                return plan(template: entry.blocks, on: entry.day, existing: sameDay,
                            moveExisting: moveExisting, bufferMinutes: bufferMinutes,
                            notBefore: notBefore, calendar: calendar)
            }
    }

    /// The events that should block a template: everything except missed and
    /// displaced ones (they occupy no time — same rule as
    /// `SchedulerService.conflicts`).
    static func existingItems(from events: [Event]) -> [ExistingItem] {
        events
            .filter { $0.status != .missed && $0.status != .displaced }
            .map { (event: Event) -> ExistingItem in
                ExistingItem(id: event.id, title: event.title, start: event.startTime, end: event.endTime,
                             isRecurring: event.isRecurring, isImported: event.source == .imported)
            }
    }

    // MARK: - Gap search

    private struct Occupied {
        let start: Date
        let end: Date
        let isTemplate: Bool
    }

    /// Buffer between two intervals: none between two template blocks,
    /// `buffer` for any pair involving an existing event.
    private static func pad(_ candidateIsTemplate: Bool, _ other: Occupied, _ buffer: TimeInterval) -> TimeInterval {
        candidateIsTemplate && other.isTemplate ? 0 : buffer
    }

    private static func fits(start: Date, end: Date, isTemplate: Bool, occupied: [Occupied],
                             buffer: TimeInterval, window: (start: Date, end: Date)) -> Bool {
        guard start >= window.start, end <= window.end else { return false }
        return !occupied.contains { o in
            let p = pad(isTemplate, o, buffer)
            return start < o.end + p && end > o.start - p
        }
    }

    /// The start time closest to `preferred` at which `duration` fits inside
    /// the window without touching anything occupied. Ties go to the later
    /// start so a shifted block doesn't jump ahead of the one before it.
    private static func nearestGap(duration: TimeInterval, preferred: Date, isTemplate: Bool,
                                   occupied: [Occupied], buffer: TimeInterval,
                                   window: (start: Date, end: Date)) -> Date? {
        // Blocked spans as seen by this candidate (padding depends on its kind),
        // sorted and merged, then the complement within the window is the gaps.
        let blocked = occupied
            .map { o -> (Date, Date) in let p = pad(isTemplate, o, buffer); return (o.start - p, o.end + p) }
            .sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for span in blocked {
            if let last = merged.last, span.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, span.1)
            } else {
                merged.append(span)
            }
        }

        var gaps: [(Date, Date)] = []
        var cursor = window.start
        for span in merged {
            if span.0 > cursor { gaps.append((cursor, min(span.0, window.end))) }
            cursor = max(cursor, span.1)
            if cursor >= window.end { break }
        }
        if cursor < window.end { gaps.append((cursor, window.end)) }

        var best: (start: Date, distance: TimeInterval)?
        for gap in gaps where gap.1.timeIntervalSince(gap.0) >= duration {
            let latestStart = gap.1 - duration
            let start = min(max(preferred, gap.0), latestStart)
            let distance = abs(start.timeIntervalSince(preferred))
            if let current = best {
                if distance < current.distance || (distance == current.distance && start > current.start) {
                    best = (start, distance)
                }
            } else {
                best = (start, distance)
            }
        }
        return best?.start
    }
}
