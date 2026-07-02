import XCTest
import SwiftData
@testable import Cadence

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

    func addJSON() -> String {
        """
        {
          "action": "add",
          "event": { "title": "Gym", "start": "\(startISO)", "end": "\(endISO)", "category": "Health" },
          "conflict_reason": null,
          "alternatives": []
        }
        """
    }

    // MARK: - Message Building

    func testBuildsCorrectUserMessage() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { msg in
            captured = msg
            return self.addJSON()
        }
        let prefs = makePrefs()
        _ = try await service.scheduleEvent(description: "gym tomorrow morning", events: [], preferences: prefs, categories: [])

        XCTAssertTrue(captured.contains("gym tomorrow morning"), "Description missing from message")
        XCTAssertTrue(captured.contains("WorkHours=9-18"),       "Prefs missing from message")
        XCTAssertTrue(captured.contains("Schedule (next 72h)"),  "Schedule header missing")
    }

    // MARK: - Response Parsing

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
          "conflict_reason": "Overlaps with Work 09:00-10:00",
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
          "conflict_reason": null,
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
        { "action": "teleport", "event": null, "conflict_reason": null, "alternatives": [] }
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

    // MARK: - Helpers (extended)

    func at(_ hour: Int, _ minute: Int = 0, daysFromNow: Int = 0) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour; comps.minute = minute; comps.second = 0
        var d = Calendar.current.date(from: comps)!
        if daysFromNow != 0 { d = Calendar.current.date(byAdding: .day, value: daysFromNow, to: d)! }
        return d
    }

    /// Builds a 7-day array where Wednesday is guaranteed to be included.
    /// Used for suggestNewMeal tests that parse a "WED HH:mm" slot string.
    func makeWeekContainingWednesday() -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1=Sun … 4=Wed … 7=Sat
        let daysToWed = (4 - weekday + 7) % 7
        let wednesday = daysToWed == 0 ? today : cal.date(byAdding: .day, value: daysToWed, to: today)!
        let start = cal.date(byAdding: .day, value: -3, to: wednesday)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: - analyzeHabits

    func testAnalyzeHabitsBuildsCorrectPayload() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { msg in captured = msg; return "Great week!" }

        let summary = HabitWeekSummary(name: "Gym", type: .good, weekTotal: 4, priorWeekTotal: 2)
        _ = try await service.analyzeHabits([summary])

        XCTAssertTrue(captured.contains("HABITS_WEEK:"), "Payload missing HABITS_WEEK header")
        XCTAssertTrue(captured.contains("Gym=4"),        "Payload missing habit name and count")
        XCTAssertTrue(captured.contains("↑"),            "Payload missing up-trend indicator")
    }

    func testAnalyzeHabitsDownTrendIndicator() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { msg in captured = msg; return "Keep it up!" }

        let summary = HabitWeekSummary(name: "Smoking", type: .bad, weekTotal: 2, priorWeekTotal: 5)
        _ = try await service.analyzeHabits([summary])

        XCTAssertTrue(captured.contains("↓"))
    }

    func testAnalyzeHabitsEmptySummariesReturnsEmptyString() async throws {
        let service = AIService()
        let result = try await service.analyzeHabits([])
        XCTAssertEqual(result, "")
    }

    func testAnalyzeHabitsReturnsRawTextFromAPI() async throws {
        var service = AIService()
        let expected = "You're crushing it this week!"
        service._callAPI = { _ in expected }

        let summary = HabitWeekSummary(name: "Sleep", type: .good, weekTotal: 7, priorWeekTotal: 5)
        let result = try await service.analyzeHabits([summary])
        XCTAssertEqual(result, expected)
    }

    // MARK: - suggestNewMeal

    func testSuggestNewMealParsesSuccessfulResponse() async throws {
        let json = """
        {
          "meal": {
            "name": "Thai Green Curry",
            "prepTimeMinutes": 40,
            "tags": ["spicy", "one-pot"],
            "scheduledSlot": "WED 20:00"
          }
        }
        """
        var service = AIService()
        service._callAPI = { _ in json }
        let prefs = makePrefs()

        let result = try await service.suggestNewMeal(
            existingMeals: [],
            freeDinnerSlots: [],
            preferences: prefs,
            referenceWeek: makeWeekContainingWednesday()
        )

        XCTAssertEqual(result.meal.name, "Thai Green Curry")
        XCTAssertEqual(result.meal.prepTimeMinutes, 40)
        XCTAssertEqual(result.meal.tags, ["spicy", "one-pot"])

        let comps = Calendar.current.dateComponents([.hour, .minute], from: result.scheduledStart)
        XCTAssertEqual(comps.hour,   20)
        XCTAssertEqual(comps.minute, 0)
    }

    func testSuggestNewMealSetsIsUserDefinedFalse() async throws {
        let json = """
        {
          "meal": {
            "name": "Shakshuka",
            "prepTimeMinutes": 25,
            "tags": [],
            "scheduledSlot": "WED 19:30"
          }
        }
        """
        var service = AIService()
        service._callAPI = { _ in json }

        let result = try await service.suggestNewMeal(
            existingMeals: [], freeDinnerSlots: [],
            preferences: makePrefs(), referenceWeek: makeWeekContainingWednesday()
        )

        XCTAssertFalse(result.meal.isUserDefined, "AI-suggested meals must have isUserDefined = false")
    }

    func testSuggestNewMealThrowsOnMalformedJSON() async {
        var service = AIService()
        service._callAPI = { _ in "not json {{" }

        do {
            _ = try await service.suggestNewMeal(
                existingMeals: [], freeDinnerSlots: [],
                preferences: makePrefs(), referenceWeek: makeWeekContainingWednesday()
            )
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSuggestNewMealThrowsWhenSlotNotInReferenceWeek() async {
        // The slot says "WED" but we pass an empty reference week → parseSlot returns nil
        let json = """
        {
          "meal": {
            "name": "Curry",
            "prepTimeMinutes": 30,
            "tags": [],
            "scheduledSlot": "WED 20:00"
          }
        }
        """
        var service = AIService()
        service._callAPI = { _ in json }

        do {
            _ = try await service.suggestNewMeal(
                existingMeals: [], freeDinnerSlots: [],
                preferences: makePrefs(), referenceWeek: [] // empty → slot not found
            )
            XCTFail("Should have thrown")
        } catch AIServiceError.invalidResponse {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - moveEvent

    func testMoveEventBuildsMessageContainingAnchorAndReason() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { msg in captured = msg; return self.addJSON() }

        let prefs = makePrefs()
        let event = Event(title: "Work Meeting", startTime: at(14), endTime: at(15))
        context.insert(event)

        _ = try await service.moveEvent(event: event, reason: "dentist conflict", allEvents: [event], preferences: prefs)

        XCTAssertTrue(captured.contains("ANCHOR_EVENT:"),    "Message missing ANCHOR_EVENT header")
        XCTAssertTrue(captured.contains("Work Meeting"),     "Message missing event title")
        XCTAssertTrue(captured.contains("dentist conflict"), "Message missing move reason")
    }

    // MARK: - rescheduleMissed

    func testRescheduleMissedBuildsMessageWithMissedCount() async throws {
        var captured = ""
        var service = AIService()
        service._callAPI = { msg in captured = msg; return self.addJSON() }

        let prefs = makePrefs()
        let event = Event(title: "Gym", startTime: at(7, daysFromNow: -1), endTime: at(8, daysFromNow: -1))
        event.status = .missed
        context.insert(event)

        _ = try await service.rescheduleMissed(event: event, missedCount: 3, allEvents: [], preferences: prefs)

        XCTAssertTrue(captured.contains("MISSED_EVENT:"), "Message missing MISSED_EVENT header")
        XCTAssertTrue(captured.contains("missed_count=3"), "Message missing missed count")
        XCTAssertTrue(captured.contains("Gym"),            "Message missing event title")
    }
}
