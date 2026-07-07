import Foundation

// MARK: - Public Output Types

enum SchedulingDecision {
    case add(EventDraft)
    case conflict(reason: String, alternatives: [EventDraft])
    case suggestAlternative([EventDraft])
}

struct EventDraft {
    var title: String
    var start: Date
    var end: Date
    var categoryName: String
}

struct ProjectPhaseData {
    var title: String
    var subtasks: [String]
    var targetDate: Date?
}

enum AIServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case networkError(Error)
    // /v1 uniform error envelope: { error: { code, message } }
    case serverError(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:          return "The AI returned an unexpected response."
        case .apiError(let code):       return "API error (HTTP \(code))."
        case .networkError(let error):  return error.localizedDescription
        case .serverError(let code, let message):
            switch code {
            case "AI_UNPARSEABLE": return "The AI couldn't produce a usable answer. Try rephrasing."
            case "TIMEOUT":        return "The AI request timed out. Try again."
            case "AI_UPSTREAM":    return "The AI service is unavailable right now."
            default:               return message
            }
        }
    }
}

// MARK: - Service

/// Thin typed-DTO client for the /v1 planning API (BACKEND_PLAN.md §3).
/// The server owns prompts, Claude calls, parsing, and validation — this
/// struct only encodes snapshots and decodes typed decisions. It never
/// imports SwiftUI, touches SwiftData contexts, or schedules notifications.
struct AIService {
    // Update this URL each time ngrok restarts.
    static var proxyBaseURL = "https://schnapps-unsent-capably.ngrok-free.dev"

    /// Test hook: request body JSON string in → response JSON string out.
    /// Swap this in tests to exercise encode/decode without the network.
    var _callAPI: ((String) async throws -> String)?

    // MARK: Shared plumbing

    /// ISO8601 with the device's UTC offset (never Z for local zones) — the
    /// format the /v1 contract requires for every time field.
    static func deviceISOFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }

    /// Only what planning needs: today onward, plus anything awaiting rescheduling.
    static func snapshots(_ events: [Event], now: Date, iso: ISO8601DateFormatter) -> [EventSnapshotDTO] {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return events
            .filter { $0.endTime >= startOfToday || $0.status == .missed || $0.status == .displaced }
            .map { EventSnapshotDTO(event: $0, iso: iso) }
    }

    /// Encode → POST (or test hook) → response data.
    func exchange(route: String, body: Data) async throws -> Data {
        if let callAPI = _callAPI {
            let raw = try await callAPI(String(decoding: body, as: UTF8.self))
            return Data(raw.utf8)
        }
        return try await postV1(route: route, body: body)
    }

    private struct V1ErrorEnvelope: Decodable {
        struct Inner: Decodable { let code: String; let message: String }
        let error: Inner
    }

    /// POST a JSON body to a /v1 route; non-2xx responses carry the uniform
    /// error envelope which is surfaced as AIServiceError.serverError.
    private func postV1(route: String, body: Data) async throws -> Data {
        let url = URL(string: "\(AIService.proxyBaseURL)\(route)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(V1ErrorEnvelope.self, from: data) {
                throw AIServiceError.serverError(code: envelope.error.code, message: envelope.error.message)
            }
            throw AIServiceError.apiError(statusCode: http.statusCode)
        }
        return data
    }
}

// MARK: - Scheduling decisions (/v1/schedule/add | move | reschedule)

extension AIService {

    func scheduleEvent(
        description: String,
        events: [Event],
        preferences: UserPreferences,
        categories: [Category]
    ) async throws -> SchedulingDecision {
        let iso = Self.deviceISOFormatter()
        let now = Date.now
        struct Request: Encodable {
            let now: String; let timezone: String; let description: String
            let events: [EventSnapshotDTO]; let prefs: PrefsSnapshotDTO
        }
        let body = try JSONEncoder().encode(Request(
            now: iso.string(from: now),
            timezone: TimeZone.current.identifier,
            description: description,
            events: Self.snapshots(events, now: now, iso: iso),
            prefs: PrefsSnapshotDTO(preferences: preferences, categories: categories)
        ))
        return try Self.decodeDecision(await exchange(route: "/v1/schedule/add", body: body), iso: iso)
    }

    func moveEvent(
        event: Event,
        reason: String,
        allEvents: [Event],
        preferences: UserPreferences,
        categories: [Category] = []
    ) async throws -> SchedulingDecision {
        let iso = Self.deviceISOFormatter()
        let now = Date.now
        struct Request: Encodable {
            let now: String; let timezone: String
            let event: EventSnapshotDTO; let reason: String
            let events: [EventSnapshotDTO]; let prefs: PrefsSnapshotDTO
        }
        let body = try JSONEncoder().encode(Request(
            now: iso.string(from: now),
            timezone: TimeZone.current.identifier,
            event: EventSnapshotDTO(event: event, iso: iso),
            reason: reason,
            events: Self.snapshots(allEvents, now: now, iso: iso),
            prefs: PrefsSnapshotDTO(preferences: preferences, categories: categories)
        ))
        return try Self.decodeDecision(await exchange(route: "/v1/schedule/move", body: body), iso: iso)
    }

    func rescheduleMissed(
        event: Event,
        missedCount: Int,
        allEvents: [Event],
        preferences: UserPreferences,
        categories: [Category] = []
    ) async throws -> SchedulingDecision {
        let iso = Self.deviceISOFormatter()
        let now = Date.now
        struct Request: Encodable {
            let now: String; let timezone: String
            let event: EventSnapshotDTO; let missedCount: Int
            let events: [EventSnapshotDTO]; let prefs: PrefsSnapshotDTO
        }
        let body = try JSONEncoder().encode(Request(
            now: iso.string(from: now),
            timezone: TimeZone.current.identifier,
            event: EventSnapshotDTO(event: event, iso: iso),
            missedCount: missedCount,
            events: Self.snapshots(allEvents, now: now, iso: iso),
            prefs: PrefsSnapshotDTO(preferences: preferences, categories: categories)
        ))
        return try Self.decodeDecision(await exchange(route: "/v1/schedule/reschedule", body: body), iso: iso)
    }

    /// Typed decision from the server: { action, event, conflictReason, alternatives }.
    static func decodeDecision(_ data: Data, iso: ISO8601DateFormatter) throws -> SchedulingDecision {
        struct Raw: Decodable {
            struct Draft: Decodable { let title: String; let start: String; let end: String; let category: String }
            struct Slot: Decodable { let start: String; let end: String }
            let action: String
            let event: Draft?
            let conflictReason: String?
            let alternatives: [Slot]
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
            throw AIServiceError.invalidResponse
        }

        func date(_ s: String) throws -> Date {
            guard let d = iso.date(from: s) else { throw AIServiceError.invalidResponse }
            return d
        }
        func slots(_ raw: [Raw.Slot]) throws -> [EventDraft] {
            try raw.map { EventDraft(title: "", start: try date($0.start), end: try date($0.end), categoryName: "") }
        }

        switch raw.action {
        case "add":
            guard let ev = raw.event else { throw AIServiceError.invalidResponse }
            return .add(EventDraft(title: ev.title, start: try date(ev.start), end: try date(ev.end), categoryName: ev.category))
        case "conflict":
            return .conflict(reason: raw.conflictReason ?? "", alternatives: try slots(raw.alternatives))
        case "suggest_alternative":
            return .suggestAlternative(try slots(raw.alternatives))
        default:
            throw AIServiceError.invalidResponse
        }
    }
}

// MARK: - Habit Analysis (/v1/habits/analysis)

extension AIService {
    func analyzeHabits(_ summaries: [HabitWeekSummary]) async throws -> String {
        guard !summaries.isEmpty else { return "" }
        struct Request: Encodable {
            struct Habit: Encodable { let name: String; let weekTotal: Int; let priorWeekTotal: Int }
            let habits: [Habit]
        }
        struct Response: Decodable { let insight: String }
        let body = try JSONEncoder().encode(Request(
            habits: summaries.map { .init(name: $0.name, weekTotal: $0.weekTotal, priorWeekTotal: $0.priorWeekTotal) }
        ))
        let data = try await exchange(route: "/v1/habits/analysis", body: body)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return response.insight
    }
}

// MARK: - Meal Suggestions (/v1/meal/suggestions)

extension AIService {

    struct MealSuggestionResult {
        var meal: Meal
        var scheduledStart: Date
        var scheduledEnd: Date
    }

    /// Returns up to 3 new-meal options scheduled into today's free dinner
    /// slots (the server computes slots and clamps to the dinner window).
    /// Callers must respect the daily fetch cap
    /// (UserPreferences.canFetchMealSuggestion) before invoking.
    func suggestMealOptions(
        existingMeals: [Meal],
        events: [Event],
        preferences: UserPreferences,
        categories: [Category] = []
    ) async throws -> [MealSuggestionResult] {
        let iso = Self.deviceISOFormatter()
        let now = Date.now
        struct Request: Encodable {
            struct MealDTO: Encodable { let name: String; let prepTimeMinutes: Int }
            let now: String; let timezone: String; let days: Int
            let existingMeals: [MealDTO]
            let events: [EventSnapshotDTO]; let prefs: PrefsSnapshotDTO
        }
        let body = try JSONEncoder().encode(Request(
            now: iso.string(from: now),
            timezone: TimeZone.current.identifier,
            days: 1, // meals are planned during the day, not a week ahead
            existingMeals: existingMeals.map { .init(name: $0.name, prepTimeMinutes: $0.prepTimeMinutes) },
            events: Self.snapshots(events, now: now, iso: iso),
            prefs: PrefsSnapshotDTO(preferences: preferences, categories: categories)
        ))
        let data = try await exchange(route: "/v1/meal/suggestions", body: body)

        struct Response: Decodable {
            struct Item: Decodable {
                let name: String; let prepTimeMinutes: Int
                let tags: [String]; let start: String; let end: String
            }
            let suggestions: [Item]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return try response.suggestions.map { item in
            guard let start = iso.date(from: item.start), let end = iso.date(from: item.end) else {
                throw AIServiceError.invalidResponse
            }
            let meal = Meal(name: item.name, prepTimeMinutes: item.prepTimeMinutes, isUserDefined: false)
            meal.tags = item.tags
            return MealSuggestionResult(meal: meal, scheduledStart: start, scheduledEnd: end)
        }
    }
}

// MARK: - Deep Project Plan (/v1/project/plan)

extension AIService {
    func deepProjectPlan(
        goal: String,
        deadline: Date,
        weeklyHours: Int,
        constraints: String
    ) async throws -> [ProjectPhaseData] {
        struct Request: Encodable {
            let now: String; let timezone: String
            let goal: String; let deadline: String
            let weeklyHours: Int; let constraints: String
        }
        struct Response: Decodable {
            struct Phase: Decodable { let title: String; let subtasks: [String]; let targetDate: String? }
            let phases: [Phase]
        }

        let iso = Self.deviceISOFormatter()
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.locale = Locale(identifier: "en_US_POSIX")

        let body = try JSONEncoder().encode(Request(
            now: iso.string(from: .now),
            timezone: TimeZone.current.identifier,
            goal: goal,
            deadline: dayFmt.string(from: deadline),
            weeklyHours: weeklyHours,
            constraints: constraints
        ))
        let data = try await exchange(route: "/v1/project/plan", body: body)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return response.phases.map { phase in
            ProjectPhaseData(
                title: phase.title,
                subtasks: phase.subtasks,
                targetDate: phase.targetDate.flatMap { dayFmt.date(from: $0) }
            )
        }
    }
}
