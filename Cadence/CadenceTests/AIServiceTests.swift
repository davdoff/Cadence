import XCTest
import SwiftData
@testable import Cadence

/// AIService is now a thin /v1 DTO exchange (BACKEND_PLAN.md Phase 2): these
/// tests verify request encoding and typed-response decoding. Prompt building
/// and model-output parsing live on the server and are covered by its node
/// test suite — not re-tested here.
///
/// `_callAPI` semantics: request body JSON string in → response JSON string out.
final class AIServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    // Fixed future dates — stable regardless of when tests run
    let startISO = "2030-06-15T09:00:00Z"
    let endISO   = "2030-06-15T10:00:00Z"
    let altISO   = "2030-06-15T14:00:00Z"
    let altEndISO = "2030-06-15T15:00:00Z"

    override func setUp() {
        super.setUp()
        let schema = Schema([Event.self, Cadence.Category.self, Meal.self, UserPreferences.self])
        container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func makeService(returning json: String) -> AIService {
        var service = AIService()
        service._callAPI = { _ in json }
        return service
    }

    func makePrefs() -> UserPreferences {
        let p = UserPreferences()
        context.insert(p)
        return p
    }

    /// Decode a captured request body for structural assertions.
    func bodyJSON(_ captured: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(captured.utf8))) as? [String: Any] ?? [:]
    }

    func addJSON() -> String {
        """
        {
          "action": "add",
          "event": { "title": "Gym", "start": "\(startISO)", "end": "\(endISO)", "category": "Health" },
          "conflictReason": null,
          "alternatives": []
        }
        """
    }

    // MARK: - scheduleEvent: request encoding

    func testScheduleEventEncodesSnapshotRequest() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in captured = body; return self.addJSON() }

        let prefs = makePrefs()
        let event = Event(title: "Standup", startTime: .now.addingTimeInterval(3600), endTime: .now.addingTimeInterval(7200))
        context.insert(event)

        _ = try await service.scheduleEvent(description: "gym tomorrow morning", events: [event], preferences: prefs, categories: [])

        let body = bodyJSON(captured)
        XCTAssertEqual(body["description"] as? String, "gym tomorrow morning")
        XCTAssertEqual(body["timezone"] as? String, TimeZone.current.identifier)
        XCTAssertNotNil(body["now"] as? String)

        let events = body["events"] as? [[String: Any]]
        XCTAssertEqual(events?.count, 1)
        XCTAssertEqual(events?.first?["title"] as? String, "Standup")
        XCTAssertEqual(events?.first?["id"] as? String, event.id.uuidString)

        let prefsDict = body["prefs"] as? [String: Any]
        XCTAssertEqual(prefsDict?["workStartHour"] as? Int, 9)
        XCTAssertEqual(prefsDict?["workEndHour"] as? Int, 18)
        XCTAssertEqual(prefsDict?["aiLevel"] as? String, "balanced")
    }

    func testSnapshotsExcludePastButKeepMissedAndDisplaced() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in captured = body; return self.addJSON() }

        let old = Event(title: "Old", startTime: .now.addingTimeInterval(-172800), endTime: .now.addingTimeInterval(-169200))
        let missed = Event(title: "Missed", startTime: .now.addingTimeInterval(-172800), endTime: .now.addingTimeInterval(-169200))
        missed.status = .missed
        let displaced = Event(title: "Displaced", startTime: .now.addingTimeInterval(-172800), endTime: .now.addingTimeInterval(-169200))
        displaced.status = .displaced
        [old, missed, displaced].forEach { context.insert($0) }

        _ = try await service.scheduleEvent(description: "x", events: [old, missed, displaced], preferences: makePrefs(), categories: [])

        let titles = (bodyJSON(captured)["events"] as? [[String: Any]])?.compactMap { $0["title"] as? String } ?? []
        XCTAssertEqual(Set(titles), ["Missed", "Displaced"], "Past events dropped; missed/displaced kept for rescheduling")
    }

    // MARK: - scheduleEvent: decision decoding

    func testParsesAddDecision() async throws {
        let decision = try await makeService(returning: addJSON())
            .scheduleEvent(description: "gym", events: [], preferences: makePrefs(), categories: [])

        guard case .add(let draft) = decision else { XCTFail("Expected .add, got \(decision)"); return }
        XCTAssertEqual(draft.title, "Gym")
        XCTAssertEqual(draft.categoryName, "Health")
    }

    func testParsesConflictDecision() async throws {
        let json = """
        {
          "action": "conflict",
          "event": null,
          "conflictReason": "Overlaps with Work 09:00-10:00",
          "alternatives": [{ "start": "\(altISO)", "end": "\(altEndISO)" }]
        }
        """
        let decision = try await makeService(returning: json)
            .scheduleEvent(description: "gym", events: [], preferences: makePrefs(), categories: [])

        guard case .conflict(let reason, let alts) = decision else { XCTFail("Expected .conflict"); return }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(alts.count, 1)
    }

    func testParsesSuggestAlternativeDecision() async throws {
        let json = """
        {
          "action": "suggest_alternative",
          "event": null,
          "conflictReason": null,
          "alternatives": [
            { "start": "\(startISO)", "end": "\(endISO)" },
            { "start": "\(altISO)", "end": "\(altEndISO)" }
          ]
        }
        """
        let decision = try await makeService(returning: json)
            .scheduleEvent(description: "gym sometime", events: [], preferences: makePrefs(), categories: [])

        guard case .suggestAlternative(let alts) = decision else { XCTFail("Expected .suggestAlternative"); return }
        XCTAssertEqual(alts.count, 2)
    }

    func testThrowsOnMalformedJSON() async {
        let service = makeService(returning: "not json at all {{{}}")
        do {
            _ = try await service.scheduleEvent(description: "gym", events: [], preferences: makePrefs(), categories: [])
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testThrowsOnUnknownAction() async {
        let json = """
        { "action": "teleport", "event": null, "conflictReason": null, "alternatives": [] }
        """
        let service = makeService(returning: json)
        do {
            _ = try await service.scheduleEvent(description: "gym", events: [], preferences: makePrefs(), categories: [])
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testISO8601DateParsing() async throws {
        let decision = try await makeService(returning: addJSON())
            .scheduleEvent(description: "gym", events: [], preferences: makePrefs(), categories: [])

        guard case .add(let draft) = decision else { XCTFail("Expected .add"); return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: draft.start)
        XCTAssertEqual(comps.year,  2030)
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.day,   15)
        XCTAssertEqual(comps.hour,  9)
        XCTAssertEqual(comps.minute, 0)
    }

    // MARK: - moveEvent / rescheduleMissed: request encoding

    func testMoveEventEncodesAnchorAndReason() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in captured = body; return self.addJSON() }

        let event = Event(title: "Work Meeting", startTime: .now.addingTimeInterval(3600), endTime: .now.addingTimeInterval(7200))
        context.insert(event)

        _ = try await service.moveEvent(event: event, reason: "dentist conflict", allEvents: [event], preferences: makePrefs())

        let body = bodyJSON(captured)
        XCTAssertEqual(body["reason"] as? String, "dentist conflict")
        let anchor = body["event"] as? [String: Any]
        XCTAssertEqual(anchor?["title"] as? String, "Work Meeting")
        XCTAssertEqual(anchor?["id"] as? String, event.id.uuidString)
    }

    func testRescheduleMissedEncodesMissedCount() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in captured = body; return self.addJSON() }

        let event = Event(title: "Gym", startTime: .now.addingTimeInterval(-86400), endTime: .now.addingTimeInterval(-82800))
        event.status = .missed
        context.insert(event)

        _ = try await service.rescheduleMissed(event: event, missedCount: 3, allEvents: [], preferences: makePrefs())

        let body = bodyJSON(captured)
        XCTAssertEqual(body["missedCount"] as? Int, 3)
        XCTAssertEqual((body["event"] as? [String: Any])?["title"] as? String, "Gym")
        XCTAssertEqual((body["event"] as? [String: Any])?["status"] as? String, "missed")
    }

    // MARK: - analyzeHabits

    func testAnalyzeHabitsEncodesSummaries() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in captured = body; return #"{ "insight": "Great week!" }"# }

        let summary = HabitWeekSummary(name: "Gym", type: .good, weekTotal: 4, priorWeekTotal: 2)
        let result = try await service.analyzeHabits([summary])

        XCTAssertEqual(result, "Great week!")
        let habits = bodyJSON(captured)["habits"] as? [[String: Any]]
        XCTAssertEqual(habits?.count, 1)
        XCTAssertEqual(habits?.first?["name"] as? String, "Gym")
        XCTAssertEqual(habits?.first?["weekTotal"] as? Int, 4)
        XCTAssertEqual(habits?.first?["priorWeekTotal"] as? Int, 2)
    }

    func testAnalyzeHabitsEmptySummariesReturnsEmptyString() async throws {
        let service = AIService()
        let result = try await service.analyzeHabits([])
        XCTAssertEqual(result, "")
    }

    func testAnalyzeHabitsThrowsOnMalformedResponse() async {
        let service = makeService(returning: "prose, not JSON")
        let summary = HabitWeekSummary(name: "Sleep", type: .good, weekTotal: 7, priorWeekTotal: 5)
        do {
            _ = try await service.analyzeHabits([summary])
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - suggestMealOptions

    func suggestionsJSON() -> String {
        """
        {
          "suggestions": [
            { "name": "Thai Green Curry", "prepTimeMinutes": 40, "tags": ["spicy", "one-pot"],
              "start": "\(startISO)", "end": "\(endISO)" },
            { "name": "Shakshuka", "prepTimeMinutes": 25, "tags": ["vegetarian"],
              "start": "\(altISO)", "end": "\(altEndISO)" }
          ]
        }
        """
    }

    func testSuggestMealOptionsRequestsTodayOnly() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in captured = body; return self.suggestionsJSON() }

        let meal = Meal(name: "Pasta", prepTimeMinutes: 30, isUserDefined: true)
        context.insert(meal)
        _ = try await service.suggestMealOptions(existingMeals: [meal], events: [], preferences: makePrefs())

        let body = bodyJSON(captured)
        XCTAssertEqual(body["days"] as? Int, 1, "Meals are planned during the day, not a week ahead")
        let meals = body["existingMeals"] as? [[String: Any]]
        XCTAssertEqual(meals?.first?["name"] as? String, "Pasta")
        XCTAssertEqual(meals?.first?["prepTimeMinutes"] as? Int, 30)
    }

    func testSuggestMealOptionsDecodesTypedSuggestions() async throws {
        let results = try await makeService(returning: suggestionsJSON())
            .suggestMealOptions(existingMeals: [], events: [], preferences: makePrefs())

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].meal.name, "Thai Green Curry")
        XCTAssertEqual(results[0].meal.prepTimeMinutes, 40)
        XCTAssertEqual(results[0].meal.tags, ["spicy", "one-pot"])
        XCTAssertTrue(results.allSatisfy { !$0.meal.isUserDefined },
                      "AI-suggested meals must have isUserDefined = false")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.hour, .minute], from: results[0].scheduledStart)
        XCTAssertEqual(comps.hour,   9)
        XCTAssertEqual(comps.minute, 0)
    }

    func testSuggestMealOptionsThrowsOnMalformedJSON() async {
        let service = makeService(returning: "not json {{")
        do {
            _ = try await service.suggestMealOptions(existingMeals: [], events: [], preferences: makePrefs())
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - deepProjectPlan

    func testDeepProjectPlanEncodesAndDecodes() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in
            captured = body
            return """
            { "phases": [
                { "title": "Research", "subtasks": ["Read docs", "Take notes"], "targetDate": "2030-07-01" },
                { "title": "Build", "subtasks": ["Prototype"], "targetDate": null }
            ] }
            """
        }

        let deadline = ISO8601DateFormatter().date(from: "2030-08-01T00:00:00Z")!
        let phases = try await service.deepProjectPlan(goal: "Learn Kotlin", deadline: deadline, weeklyHours: 6, constraints: "evenings only")

        let body = bodyJSON(captured)
        XCTAssertEqual(body["goal"] as? String, "Learn Kotlin")
        XCTAssertEqual(body["weeklyHours"] as? Int, 6)
        XCTAssertEqual(body["constraints"] as? String, "evenings only")
        XCTAssertEqual((body["deadline"] as? String)?.count, 10, "deadline must be YYYY-MM-DD")

        XCTAssertEqual(phases.count, 2)
        XCTAssertEqual(phases[0].title, "Research")
        XCTAssertEqual(phases[0].subtasks, ["Read docs", "Take notes"])
        XCTAssertNotNil(phases[0].targetDate)
        XCTAssertNil(phases[1].targetDate)
    }

    // MARK: - interpret

    func testInterpretEncodesTextAndDecodesMoveIntent() async throws {
        let targetID = UUID()
        var captured = ""
        var service = AIService()
        service._callAPI = { body in
            captured = body
            return """
            {
              "intent": "move",
              "interpretation": "Moving 'Gym' to Sat 08:00–09:00",
              "targetEventId": "\(targetID.uuidString)",
              "newStart": "\(self.startISO)",
              "newEnd": "\(self.endISO)",
              "alternatives": []
            }
            """
        }

        let decision = try await service.interpret(
            text: "move my gym to tomorrow morning",
            events: [], preferences: makePrefs(), categories: []
        )

        XCTAssertEqual(bodyJSON(captured)["text"] as? String, "move my gym to tomorrow morning")
        guard case .move(let interpretation, let id, _, _, let alts) = decision else {
            XCTFail("Expected .move, got \(decision)"); return
        }
        XCTAssertEqual(id, targetID)
        XCTAssertEqual(interpretation, "Moving 'Gym' to Sat 08:00–09:00")
        XCTAssertTrue(alts.isEmpty)
    }

    func testInterpretDecodesClarifyIntent() async throws {
        let json = """
        {
          "intent": "clarify",
          "interpretation": "Which dentist appointment?",
          "question": "You have two dentist appointments — which one?",
          "options": ["Tuesday 10:00", "Friday 14:00"]
        }
        """
        let decision = try await makeService(returning: json)
            .interpret(text: "move my dentist", events: [], preferences: makePrefs(), categories: [])

        guard case .clarify(let question, let options) = decision else {
            XCTFail("Expected .clarify, got \(decision)"); return
        }
        XCTAssertTrue(question.contains("which one"))
        XCTAssertEqual(options.count, 2)
    }

    func testInterpretDecodesReorganizeIntent() async throws {
        let moveID = UUID(); let displacedID = UUID()
        let json = """
        {
          "intent": "reorganize",
          "interpretation": "Clearing your afternoon",
          "moves": [{ "targetEventId": "\(moveID.uuidString)", "newStart": "\(startISO)", "newEnd": "\(endISO)" }],
          "displaced": ["\(displacedID.uuidString)"]
        }
        """
        let decision = try await makeService(returning: json)
            .interpret(text: "clean up my afternoon", events: [], preferences: makePrefs(), categories: [])

        guard case .reorganize(_, let moves, let displaced) = decision else {
            XCTFail("Expected .reorganize, got \(decision)"); return
        }
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].targetEventID, moveID)
        XCTAssertEqual(displaced, [displacedID])
    }

    func testInterpretThrowsOnUnknownIntent() async {
        let json = #"{ "intent": "teleport", "interpretation": "beam me up" }"#
        let service = makeService(returning: json)
        do {
            _ = try await service.interpret(text: "x", events: [], preferences: makePrefs(), categories: [])
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - generate

    func testGenerateEncodesPeriodAndDecodesDrafts() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in
            captured = body
            return """
            {
              "events": [
                { "title": "Workout", "start": "\(self.startISO)", "end": "\(self.endISO)", "category": "Health" },
                { "title": "Exam prep", "start": "\(self.altISO)", "end": "\(self.altEndISO)", "category": "Study" }
              ]
            }
            """
        }

        let iso = AIService.deviceISOFormatter()
        let periodStart = iso.date(from: "2030-06-15T00:00:00Z")!
        let periodEnd   = iso.date(from: "2030-06-21T23:59:00Z")!

        let drafts = try await service.generate(
            periodStart: periodStart, periodEnd: periodEnd,
            goals: "3 workouts and 4h exam prep",
            events: [], preferences: makePrefs(), categories: []
        )

        let body = bodyJSON(captured)
        XCTAssertEqual(body["goals"] as? String, "3 workouts and 4h exam prep")
        let period = body["period"] as? [String: Any]
        XCTAssertNotNil(period?["start"] as? String)
        XCTAssertNotNil(period?["end"] as? String)
        XCTAssertNotNil(body["now"] as? String)
        XCTAssertNotNil(body["timezone"] as? String)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].title, "Workout")
        XCTAssertEqual(drafts[1].categoryName, "Study")
    }

    func testGenerateEmptyEventsReturnsEmptyDrafts() async throws {
        let service = makeService(returning: #"{ "events": [] }"#)
        let drafts = try await service.generate(
            periodStart: .now, periodEnd: .now.addingTimeInterval(86_400),
            goals: "anything", events: [], preferences: makePrefs(), categories: []
        )
        XCTAssertTrue(drafts.isEmpty)
    }

    func testGenerateThrowsOnMalformedResponse() async {
        let service = makeService(returning: "not json")
        do {
            _ = try await service.generate(
                periodStart: .now, periodEnd: .now.addingTimeInterval(86_400),
                goals: "x", events: [], preferences: makePrefs(), categories: []
            )
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Prefs snapshot encoding

    func testPrefsSnapshotEncodesAvoidBlocksWithISOWeekdays() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { body in captured = body; return self.addJSON() }

        let prefs = makePrefs()
        // Swift Calendar: 1=Sunday, 2=Monday. ISO: 1=Monday, 7=Sunday.
        prefs.avoidScheduling = [TimeBlock(startHour: 12, startMinute: 0, endHour: 13, endMinute: 30, weekdays: [1, 2])]

        _ = try await service.scheduleEvent(description: "x", events: [], preferences: prefs, categories: [])

        let avoid = ((bodyJSON(captured)["prefs"] as? [String: Any])?["avoidScheduling"] as? [[String: Any]])?.first
        XCTAssertEqual(avoid?["weekdays"] as? [Int], [7, 1], "Sun→7, Mon→1 in ISO numbering")
        XCTAssertEqual(avoid?["start"] as? String, "12:00")
        XCTAssertEqual(avoid?["end"] as? String, "13:30")
    }

    // MARK: - Suggestion fetch cap (unchanged client logic)

    func testMealSuggestionCapAllowsTwoPerDay() {
        let p = makePrefs()
        XCTAssertTrue(p.canFetchMealSuggestion())
        p.recordMealSuggestionFetch()
        XCTAssertTrue(p.canFetchMealSuggestion())
        p.recordMealSuggestionFetch()
        XCTAssertFalse(p.canFetchMealSuggestion())
    }

    func testMealSuggestionCapResetsNextDay() {
        let p = makePrefs()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        p.recordMealSuggestionFetch(now: yesterday)
        p.recordMealSuggestionFetch(now: yesterday)
        XCTAssertFalse(p.canFetchMealSuggestion(now: yesterday))

        XCTAssertTrue(p.canFetchMealSuggestion())
        p.recordMealSuggestionFetch()
        XCTAssertEqual(p.mealSuggestionFetchCount, 1)
    }
}
