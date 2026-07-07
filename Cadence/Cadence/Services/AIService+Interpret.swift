import Foundation

// MARK: - AssistantDecision (public output of /v1/schedule/interpret)

/// Typed decision returned by the "Ask AI" secretary box (ai-planner.md §4).
/// Plain value type — views apply it to SwiftData and schedule notifications.
enum AssistantDecision {
    case add(interpretation: String, event: EventDraft?, conflictReason: String?, alternatives: [EventDraft])
    case move(interpretation: String, targetEventID: UUID, newStart: Date, newEnd: Date, alternatives: [EventDraft])
    case reschedule(interpretation: String, targetEventID: UUID, newStart: Date, newEnd: Date)
    case reorganize(interpretation: String, moves: [PlannedMove], displaced: [UUID])
    case generate(interpretation: String, events: [EventDraft])
    case clarify(question: String, options: [String])

    var interpretation: String {
        switch self {
        case .add(let i, _, _, _), .move(let i, _, _, _, _), .reschedule(let i, _, _, _),
             .reorganize(let i, _, _), .generate(let i, _):
            return i
        case .clarify(let question, _):
            return question
        }
    }
}

struct PlannedMove {
    var targetEventID: UUID
    var newStart: Date
    var newEnd: Date
}

// MARK: - Request DTOs (BACKEND_PLAN.md §3 shared request objects)

struct EventSnapshotDTO: Encodable {
    let id: String
    let title: String
    let start: String
    let end: String
    let category: String?
    let status: String

    init(event: Event, iso: ISO8601DateFormatter) {
        id = event.id.uuidString
        title = event.title
        start = iso.string(from: event.startTime)
        end = iso.string(from: event.endTime)
        category = event.category?.name
        status = event.status.rawValue
    }
}

struct PrefsSnapshotDTO: Encodable {
    struct AvoidBlock: Encodable {
        let weekdays: [Int]     // ISO: 1=Mon … 7=Sun
        let start: String       // "HH:mm"
        let end: String
    }
    struct DinnerWindow: Encodable {
        let start: String
        let end: String
    }

    let workStartHour: Int
    let workEndHour: Int
    let bufferMinutes: Int
    let priorityCategories: [String]
    let aiLevel: String
    let avoidScheduling: [AvoidBlock]
    let dinnerWindow: DinnerWindow
    let mealGuidance: String

    init(preferences p: UserPreferences, categories: [Category]) {
        workStartHour = p.workStartHour
        workEndHour = p.workEndHour
        bufferMinutes = p.bufferMinutes
        priorityCategories = categories
            .filter { p.priorityCategoryIDs.contains($0.id) }
            .map(\.name)
        switch p.aiAggressiveness {
        case ...2:  aiLevel = "passive"
        case 3:     aiLevel = "balanced"
        default:    aiLevel = "aggressive"
        }
        avoidScheduling = p.avoidScheduling.map { block in
            AvoidBlock(
                // Swift Calendar weekdays (1=Sun…7=Sat) → ISO (1=Mon…7=Sun)
                weekdays: block.weekdays.map { $0 == 1 ? 7 : $0 - 1 },
                start: String(format: "%02d:%02d", block.startHour, block.startMinute),
                end: String(format: "%02d:%02d", block.endHour, block.endMinute)
            )
        }
        dinnerWindow = DinnerWindow(
            start: String(format: "%02d:%02d", p.dinnerWindowStartHour, p.dinnerWindowStartMinute),
            end: String(format: "%02d:%02d", p.dinnerWindowEndHour, p.dinnerWindowEndMinute)
        )
        mealGuidance = p.mealGuidance
    }
}

// MARK: - Interpret

extension AIService {

    /// The single call behind the "Ask AI" box: snapshot + text in, typed decision out.
    /// The server owns the prompt, free-slot computation, parsing, and retry-once.
    func interpret(
        text: String,
        events: [Event],
        preferences: UserPreferences,
        categories: [Category]
    ) async throws -> AssistantDecision {
        let now = Date.now
        let iso = Self.deviceISOFormatter()

        let request = InterpretRequest(
            now: iso.string(from: now),
            timezone: TimeZone.current.identifier,
            text: text,
            events: Self.snapshots(events, now: now, iso: iso),
            prefs: PrefsSnapshotDTO(preferences: preferences, categories: categories)
        )
        let body = try JSONEncoder().encode(request)
        let responseData = try await exchange(route: "/v1/schedule/interpret", body: body)
        return try Self.decodeInterpret(responseData, iso: iso)
    }
}

// MARK: - Generate (/v1/schedule/generate)

extension AIService {

    /// The direct "fill this period" call (ai-planner.md §7) behind the
    /// plan-a-period sheet. Unlike the interpret `generate` intent, the period
    /// is explicit — no classification round, no 7-day window cap. The server
    /// computes free slots for the period (clipped to now) and returns the
    /// generated batch; an empty array means nothing fit.
    func generate(
        periodStart: Date,
        periodEnd: Date,
        goals: String,
        events: [Event],
        preferences: UserPreferences,
        categories: [Category]
    ) async throws -> [EventDraft] {
        let now = Date.now
        let iso = Self.deviceISOFormatter()

        let request = GenerateRequest(
            now: iso.string(from: now),
            timezone: TimeZone.current.identifier,
            period: .init(start: iso.string(from: periodStart), end: iso.string(from: periodEnd)),
            goals: goals,
            events: Self.snapshots(events, now: now, iso: iso),
            prefs: PrefsSnapshotDTO(preferences: preferences, categories: categories)
        )
        let body = try JSONEncoder().encode(request)
        let responseData = try await exchange(route: "/v1/schedule/generate", body: body)
        return try Self.decodeGenerate(responseData, iso: iso)
    }

    static func decodeGenerate(_ data: Data, iso: ISO8601DateFormatter) throws -> [EventDraft] {
        struct Response: Decodable {
            struct Draft: Decodable { let title: String; let start: String; let end: String; let category: String }
            let events: [Draft]
        }
        guard let raw = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return try raw.events.map { d in
            guard let start = iso.date(from: d.start), let end = iso.date(from: d.end) else {
                throw AIServiceError.invalidResponse
            }
            return EventDraft(title: d.title, start: start, end: end, categoryName: d.category)
        }
    }
}

private struct GenerateRequest: Encodable {
    struct Period: Encodable { let start: String; let end: String }
    let now: String
    let timezone: String
    let period: Period
    let goals: String
    let events: [EventSnapshotDTO]
    let prefs: PrefsSnapshotDTO
}

// MARK: - Interpret response decoding

private struct InterpretRequest: Encodable {
    let now: String
    let timezone: String
    let text: String
    let events: [EventSnapshotDTO]
    let prefs: PrefsSnapshotDTO
}

/// Flat union as returned by the server's parseInterpret — the intent decides
/// which optional fields are present.
private struct RawInterpret: Decodable {
    struct Draft: Decodable { let title: String; let start: String; let end: String; let category: String }
    struct Slot: Decodable { let start: String; let end: String }
    struct Move: Decodable { let targetEventId: String; let newStart: String; let newEnd: String }

    let intent: String
    let interpretation: String
    // add
    let event: Draft?
    let conflictReason: String?
    let alternatives: [Slot]?
    // move / reschedule
    let targetEventId: String?
    let newStart: String?
    let newEnd: String?
    // reorganize
    let moves: [Move]?
    let displaced: [String]?
    // generate
    let events: [Draft]?
    // clarify
    let question: String?
    let options: [String]?
}

extension AIService {

    static func decodeInterpret(_ data: Data, iso: ISO8601DateFormatter) throws -> AssistantDecision {
        guard let raw = try? JSONDecoder().decode(RawInterpret.self, from: data) else {
            throw AIServiceError.invalidResponse
        }

        func date(_ s: String?) throws -> Date {
            guard let s, let d = iso.date(from: s) else { throw AIServiceError.invalidResponse }
            return d
        }
        func uuid(_ s: String?) throws -> UUID {
            guard let s, let u = UUID(uuidString: s) else { throw AIServiceError.invalidResponse }
            return u
        }
        func draft(_ d: RawInterpret.Draft) throws -> EventDraft {
            EventDraft(title: d.title, start: try date(d.start), end: try date(d.end), categoryName: d.category)
        }
        func slots(_ raw: [RawInterpret.Slot]?) throws -> [EventDraft] {
            try (raw ?? []).map { EventDraft(title: "", start: try date($0.start), end: try date($0.end), categoryName: "") }
        }

        switch raw.intent {
        case "add":
            return .add(
                interpretation: raw.interpretation,
                event: try raw.event.map(draft),
                conflictReason: raw.conflictReason,
                alternatives: try slots(raw.alternatives)
            )
        case "move":
            return .move(
                interpretation: raw.interpretation,
                targetEventID: try uuid(raw.targetEventId),
                newStart: try date(raw.newStart),
                newEnd: try date(raw.newEnd),
                alternatives: try slots(raw.alternatives)
            )
        case "reschedule":
            return .reschedule(
                interpretation: raw.interpretation,
                targetEventID: try uuid(raw.targetEventId),
                newStart: try date(raw.newStart),
                newEnd: try date(raw.newEnd)
            )
        case "reorganize":
            guard let moves = raw.moves, !moves.isEmpty else { throw AIServiceError.invalidResponse }
            return .reorganize(
                interpretation: raw.interpretation,
                moves: try moves.map {
                    PlannedMove(targetEventID: try uuid($0.targetEventId),
                                newStart: try date($0.newStart),
                                newEnd: try date($0.newEnd))
                },
                displaced: try (raw.displaced ?? []).map { try uuid($0) }
            )
        case "generate":
            guard let events = raw.events, !events.isEmpty else { throw AIServiceError.invalidResponse }
            return .generate(interpretation: raw.interpretation, events: try events.map(draft))
        case "clarify":
            guard let question = raw.question else { throw AIServiceError.invalidResponse }
            return .clarify(question: question, options: raw.options ?? [])
        default:
            throw AIServiceError.invalidResponse
        }
    }
}
