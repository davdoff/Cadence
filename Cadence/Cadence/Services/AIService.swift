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

enum AIServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:          return "The AI returned an unexpected response."
        case .apiError(let code):       return "API error (HTTP \(code))."
        case .networkError(let error):  return error.localizedDescription
        }
    }
}

// MARK: - Service

struct AIService {
    let apiKey: String
    private let scheduler = SchedulerService()

    /// Swap this in tests to avoid hitting the real API.
    var _callAPI: ((String) async throws -> String)?

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func scheduleEvent(
        description: String,
        events: [Event],
        preferences: UserPreferences,
        categories: [Category]
    ) async throws -> SchedulingDecision {
        let now = Date.now
        let window = now...now.addingTimeInterval(72 * 3600)
        let freeSlots = scheduler.freeSlots(duration: 30, in: window, events: events, preferences: preferences)
        let message = SchedulingContextBuilder().build(
            .addToFreeSlot(description: description, freeSlots: freeSlots),
            preferences: preferences
        )
        let rawJSON: String
        if let callAPI = _callAPI {
            rawJSON = try await callAPI(message)
        } else {
            rawJSON = try await callClaude(userMessage: message)
        }
        return try parseResponse(rawJSON)
    }
}

// MARK: - Network

private extension AIService {
    func callClaude(userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey,        forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 300,
            system: AIService.systemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AIServiceError.apiError(statusCode: http.statusCode) }

        let envelope = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
        guard let text = envelope.content.first?.text else { throw AIServiceError.invalidResponse }
        return text
    }
}

// MARK: - Response Parsing

private extension AIService {
    func parseResponse(_ json: String) throws -> SchedulingDecision {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawDecision.self, from: data)
        else { throw AIServiceError.invalidResponse }

        let iso = ISO8601DateFormatter()

        func draft(title: String, start: String, end: String, category: String) throws -> EventDraft {
            guard let s = iso.date(from: start), let e = iso.date(from: end) else {
                throw AIServiceError.invalidResponse
            }
            return EventDraft(title: title, start: s, end: e, categoryName: category)
        }

        func slot(start: String, end: String) throws -> EventDraft {
            guard let s = iso.date(from: start), let e = iso.date(from: end) else {
                throw AIServiceError.invalidResponse
            }
            return EventDraft(title: "", start: s, end: e, categoryName: "")
        }

        switch raw.action {
        case "add":
            guard let ev = raw.event else { throw AIServiceError.invalidResponse }
            return .add(try draft(title: ev.title, start: ev.start, end: ev.end, category: ev.category))

        case "conflict":
            let alts = try raw.alternatives.map { try slot(start: $0.start, end: $0.end) }
            return .conflict(reason: raw.conflict_reason ?? "", alternatives: alts)

        case "suggest_alternative":
            let alts = try raw.alternatives.map { try slot(start: $0.start, end: $0.end) }
            return .suggestAlternative(alts)

        default:
            throw AIServiceError.invalidResponse
        }
    }
}

// MARK: - Habit Analysis

extension AIService {
    func analyzeHabits(_ summaries: [HabitWeekSummary]) async throws -> String {
        guard !summaries.isEmpty else { return "" }
        let payload = summaries.map { s in
            let trend = s.weekTotal > s.priorWeekTotal ? "↑" : (s.weekTotal < s.priorWeekTotal ? "↓" : "→")
            return "\(s.name)=\(s.weekTotal)(\(trend) from \(s.priorWeekTotal))"
        }.joined(separator: ", ")
        let message = "HABITS_WEEK: \(payload)"
        if let callAPI = _callAPI {
            return try await callAPI(message)
        }
        return try await callClaudeHabits(userMessage: message)
    }
}

private extension AIService {
    func callClaudeHabits(userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey,        forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 200,
            system: AIService.habitSystemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AIServiceError.apiError(statusCode: http.statusCode) }

        let envelope = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
        guard let text = envelope.content.first?.text else { throw AIServiceError.invalidResponse }
        return text
    }
}

// MARK: - Meal Suggestion

extension AIService {

    struct MealSuggestionResult {
        var meal: Meal
        var scheduledStart: Date
        var scheduledEnd: Date
    }

    /// One API call per week maximum (caller must check lastNewMealSuggestedDate before invoking).
    func suggestNewMeal(
        existingMeals: [Meal],
        freeDinnerSlots: [TimeSlot],
        preferences: UserPreferences,
        referenceWeek: [Date]
    ) async throws -> MealSuggestionResult {
        let builder = SchedulingContextBuilder()
        let message = builder.build(.mealSuggestion(existingMeals: existingMeals, freeDinnerSlots: freeDinnerSlots), preferences: preferences)

        let rawJSON: String
        if let callAPI = _callAPI {
            rawJSON = try await callAPI(message)
        } else {
            rawJSON = try await callClaudeMealSuggestion(userMessage: message)
        }

        return try parseMealSuggestion(rawJSON, referenceWeek: referenceWeek, preferences: preferences)
    }

    private func callClaudeMealSuggestion(userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey,            forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",      forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 200,
            system: AIService.mealSuggestionSystemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AIServiceError.apiError(statusCode: http.statusCode) }

        let envelope = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
        guard let text = envelope.content.first?.text else { throw AIServiceError.invalidResponse }
        return text
    }

    private func parseMealSuggestion(
        _ json: String,
        referenceWeek: [Date],
        preferences: UserPreferences
    ) throws -> MealSuggestionResult {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawMealSuggestion.self, from: data)
        else { throw AIServiceError.invalidResponse }

        let meal = Meal(name: raw.meal.name, prepTimeMinutes: raw.meal.prepTimeMinutes, isUserDefined: false)
        meal.tags = raw.meal.tags

        guard let start = parseSlot(raw.meal.scheduledSlot, referenceWeek: referenceWeek) else {
            throw AIServiceError.invalidResponse
        }
        let durationMinutes = raw.meal.prepTimeMinutes > 0 ? raw.meal.prepTimeMinutes : 45
        let windowEnd = Calendar.current.date(
            bySettingHour: preferences.dinnerWindowEndHour,
            minute: preferences.dinnerWindowEndMinute,
            second: 0, of: start
        ) ?? start.addingTimeInterval(3600)
        let end = Swift.min(start.addingTimeInterval(TimeInterval(durationMinutes * 60)), windowEnd)

        return MealSuggestionResult(meal: meal, scheduledStart: start, scheduledEnd: end)
    }

    private func parseSlot(_ slot: String, referenceWeek: [Date]) -> Date? {
        let parts = slot.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let dayAbbr = String(parts[0]).uppercased()
        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count == 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else { return nil }

        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        fmt.locale = Locale(identifier: "en_US_POSIX")

        for date in referenceWeek {
            if fmt.string(from: date).uppercased() == dayAbbr {
                return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
            }
        }
        return nil
    }
}

// MARK: - Move Event

extension AIService {
    func moveEvent(
        event: Event,
        reason: String,
        allEvents: [Event],
        preferences: UserPreferences
    ) async throws -> SchedulingDecision {
        let now = Date.now
        let window = now...now.addingTimeInterval(7 * 24 * 3600)
        let freeSlots = scheduler.freeSlots(duration: 30, in: window, events: allEvents, preferences: preferences)
        let cal = Calendar.current
        let surrounding = allEvents.filter {
            $0.id != event.id &&
            $0.status != .missed &&
            cal.isDate($0.startTime, inSameDayAs: event.startTime)
        }
        let message = SchedulingContextBuilder().build(
            .moveEvent(event: event, reason: reason, surroundingEvents: surrounding, freeSlots: freeSlots),
            preferences: preferences
        )
        let rawJSON: String
        if let callAPI = _callAPI {
            rawJSON = try await callAPI(message)
        } else {
            rawJSON = try await callClaude(userMessage: message)
        }
        return try parseResponse(rawJSON)
    }
}

// MARK: - Reschedule Missed

extension AIService {
    func rescheduleMissed(
        event: Event,
        missedCount: Int,
        allEvents: [Event],
        preferences: UserPreferences
    ) async throws -> SchedulingDecision {
        let now = Date.now
        let window = now...now.addingTimeInterval(7 * 24 * 3600)
        let freeSlots = scheduler.freeSlots(duration: 30, in: window, events: allEvents, preferences: preferences)
        let message = SchedulingContextBuilder().build(
            .rescheduleMissed(event: event, missedCount: missedCount, freeSlots: freeSlots),
            preferences: preferences
        )
        let rawJSON: String
        if let callAPI = _callAPI {
            rawJSON = try await callAPI(message)
        } else {
            rawJSON = try await callClaude(userMessage: message)
        }
        return try parseResponse(rawJSON)
    }
}

// MARK: - Deep Project Plan

struct ProjectPhaseData {
    var title: String
    var subtasks: [String]
    var targetDate: Date?
}

extension AIService {
    func deepProjectPlan(
        goal: String,
        deadline: Date,
        weeklyHours: Int,
        constraints: String,
        preferences: UserPreferences
    ) async throws -> [ProjectPhaseData] {
        let message = SchedulingContextBuilder().build(
            .deepProjectPlan(goal: goal, deadline: deadline, weeklyHours: weeklyHours, constraints: constraints),
            preferences: preferences
        )
        let rawJSON: String
        if let callAPI = _callAPI {
            rawJSON = try await callAPI(message)
        } else {
            rawJSON = try await callClaudeProjectPlan(userMessage: message)
        }
        return try parseProjectPlan(rawJSON)
    }
}

private extension AIService {
    func callClaudeProjectPlan(userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = ClaudeRequest(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 600,
            system: AIService.projectPlanSystemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AIServiceError.apiError(statusCode: http.statusCode) }

        let envelope = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
        guard let text = envelope.content.first?.text else { throw AIServiceError.invalidResponse }
        return text
    }

    func parseProjectPlan(_ json: String) throws -> [ProjectPhaseData] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawProjectPlan.self, from: data)
        else { throw AIServiceError.invalidResponse }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")

        return raw.phases.map { phase in
            ProjectPhaseData(
                title: phase.title,
                subtasks: phase.subtasks,
                targetDate: phase.targetDate.flatMap { fmt.date(from: $0) }
            )
        }
    }
}

private struct RawProjectPlan: Decodable {
    struct Phase: Decodable {
        let title: String
        let subtasks: [String]
        let targetDate: String?
    }
    let phases: [Phase]
}

private struct RawMealSuggestion: Decodable {
    struct MealData: Decodable {
        let name: String
        let prepTimeMinutes: Int
        let tags: [String]
        let scheduledSlot: String
    }
    let meal: MealData
}

// MARK: - Private Codable Types

private struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ClaudeAPIResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable { let text: String }
}

private struct RawDecision: Decodable {
    let action: String
    let event: RawEvent?
    let conflict_reason: String?
    let alternatives: [RawSlot]

    struct RawEvent: Decodable {
        let title: String
        let start: String
        let end: String
        let category: String
    }
    struct RawSlot: Decodable {
        let start: String
        let end: String
    }
}
