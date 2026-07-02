import XCTest
import SwiftData
@testable import Cadence

final class ContextBuilderTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    let builder = SchedulingContextBuilder()

    override func setUp() {
        super.setUp()
        let schema = Schema([Event.self, Cadence.Category.self, Meal.self, UserPreferences.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func makePrefs() -> UserPreferences {
        let p = UserPreferences()
        context.insert(p)
        return p
    }

    /// Returns a TimeSlot (DateInterval) at tomorrow 10:00–11:00.
    func makeSlot(startHour: Int = 10, endHour: Int = 11, daysFromNow: Int = 1) -> TimeSlot {
        let cal = Calendar.current
        let base = cal.startOfDay(for: cal.date(byAdding: .day, value: daysFromNow, to: Date())!)
        let start = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: base)!
        let end   = cal.date(bySettingHour: endHour,   minute: 0, second: 0, of: base)!
        return DateInterval(start: start, end: end)
    }

    func makeEvent(title: String, startHour: Int, endHour: Int, daysFromNow: Int = 0) -> Event {
        let cal = Calendar.current
        let base = cal.startOfDay(for: cal.date(byAdding: .day, value: daysFromNow, to: Date())!)
        let start = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: base)!
        let end   = cal.date(bySettingHour: endHour,   minute: 0, second: 0, of: base)!
        let e = Event(title: title, startTime: start, endTime: end)
        context.insert(e)
        return e
    }

    func makeMeal(name: String, prep: Int) -> Meal {
        let m = Meal(name: name, prepTimeMinutes: prep)
        context.insert(m)
        return m
    }

    // MARK: - addToFreeSlot

    func testAddToFreeSlotContainsDescription() {
        let prefs = makePrefs()
        let slot = makeSlot()
        let output = builder.build(.addToFreeSlot(description: "dentist appointment", freeSlots: [slot]), preferences: prefs)
        XCTAssertTrue(output.contains("dentist appointment"))
    }

    func testAddToFreeSlotContainsFreeSlots() {
        let prefs = makePrefs()
        let slot = makeSlot()
        let output = builder.build(.addToFreeSlot(description: "test", freeSlots: [slot]), preferences: prefs)
        XCTAssertTrue(output.contains("FREE_SLOTS:"))
    }

    func testAddToFreeSlotContainsBuffer() {
        let prefs = makePrefs() // default buffer = 15 min
        let output = builder.build(.addToFreeSlot(description: "test", freeSlots: []), preferences: prefs)
        XCTAssertTrue(output.contains("BufferBetweenEvents=15min"))
    }

    func testAddToFreeSlotEmptySlotsStillValid() {
        let prefs = makePrefs()
        let output = builder.build(.addToFreeSlot(description: "yoga class", freeSlots: []), preferences: prefs)
        XCTAssertTrue(output.contains("yoga class"))
        XCTAssertFalse(output.isEmpty)
    }

    // MARK: - moveEvent

    func testMoveEventContainsAnchorEventHeader() {
        let prefs = makePrefs()
        let event = makeEvent(title: "Work Meeting", startHour: 14, endHour: 15)
        let slot = makeSlot()
        let output = builder.build(
            .moveEvent(event: event, reason: "dentist conflict", surroundingEvents: [], freeSlots: [slot]),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("ANCHOR_EVENT:"))
        XCTAssertTrue(output.contains("Work Meeting"))
    }

    func testMoveEventContainsReason() {
        let prefs = makePrefs()
        let event = makeEvent(title: "Standup", startHour: 9, endHour: 10)
        let output = builder.build(
            .moveEvent(event: event, reason: "flight rescheduled", surroundingEvents: [], freeSlots: []),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("flight rescheduled"))
        XCTAssertTrue(output.contains("REASON_FOR_MOVE:"))
    }

    func testMoveEventNoSurroundingEventsShowsNone() {
        let prefs = makePrefs()
        let event = makeEvent(title: "Gym", startHour: 7, endHour: 8)
        let output = builder.build(
            .moveEvent(event: event, reason: "busy", surroundingEvents: [], freeSlots: []),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("SURROUNDING_EVENTS: none"))
    }

    func testMoveEventListsSurroundingEvents() {
        let prefs = makePrefs()
        let anchor = makeEvent(title: "Work Meeting", startHour: 14, endHour: 15)
        let nearby = makeEvent(title: "Study", startHour: 15, endHour: 16)
        let output = builder.build(
            .moveEvent(event: anchor, reason: "conflict", surroundingEvents: [nearby], freeSlots: []),
            preferences: prefs
        )
        XCTAssertFalse(output.contains("SURROUNDING_EVENTS: none"))
        XCTAssertTrue(output.contains("Study") || output.contains("15:00"))
    }

    // MARK: - rescheduleMissed

    func testRescheduleMissedContainsEventTitle() {
        let prefs = makePrefs()
        let event = makeEvent(title: "Gym Session", startHour: 7, endHour: 8)
        event.status = .missed
        let output = builder.build(
            .rescheduleMissed(event: event, missedCount: 2, freeSlots: [makeSlot()]),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("Gym Session"))
        XCTAssertTrue(output.contains("MISSED_EVENT:"))
    }

    func testRescheduleMissedContainsMissedCount() {
        let prefs = makePrefs()
        let event = makeEvent(title: "Reading", startHour: 20, endHour: 21)
        let output = builder.build(
            .rescheduleMissed(event: event, missedCount: 3, freeSlots: []),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("missed_count=3"))
    }

    func testRescheduleMissedContainsFreeSlots() {
        let prefs = makePrefs()
        let event = makeEvent(title: "Run", startHour: 6, endHour: 7)
        let output = builder.build(
            .rescheduleMissed(event: event, missedCount: 1, freeSlots: [makeSlot()]),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("FREE_SLOTS (next 7d):"))
    }

    // MARK: - mealSuggestion

    func testMealSuggestionContainsIntentHeader() {
        let prefs = makePrefs()
        let output = builder.build(
            .mealSuggestion(existingMeals: [], freeDinnerSlots: []),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("INTENT: new_meal_suggestion"))
    }

    func testMealSuggestionContainsExistingMealNames() {
        let prefs = makePrefs()
        let pasta = makeMeal(name: "Pasta Bolognese", prep: 45)
        let stirFry = makeMeal(name: "Stir Fry", prep: 30)
        let output = builder.build(
            .mealSuggestion(existingMeals: [pasta, stirFry], freeDinnerSlots: []),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("Pasta Bolognese(45min)"))
        XCTAssertTrue(output.contains("Stir Fry(30min)"))
    }

    func testMealSuggestionContainsDinnerWindow() {
        let prefs = makePrefs() // default 19:00-22:00
        let output = builder.build(
            .mealSuggestion(existingMeals: [], freeDinnerSlots: []),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("dinnerWindow=19:00-22:00"))
    }

    func testMealSuggestionContainsFreeDinnerSlots() {
        let prefs = makePrefs()
        let slot = makeSlot(startHour: 19, endHour: 21)
        let output = builder.build(
            .mealSuggestion(existingMeals: [], freeDinnerSlots: [slot]),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("FREE_DINNER_SLOTS:"))
        XCTAssertTrue(output.contains("19:00"))
    }

    func testMealSuggestionContainsGuidanceWhenSet() {
        let prefs = makePrefs()
        prefs.mealGuidance = "vegetarian, rice dishes"
        let output = builder.build(
            .mealSuggestion(existingMeals: [], freeDinnerSlots: []),
            preferences: prefs
        )
        XCTAssertTrue(output.contains("GUIDANCE: \"vegetarian, rice dishes\""))
    }

    func testMealSuggestionOmitsGuidanceWhenEmpty() {
        let prefs = makePrefs()
        prefs.mealGuidance = "   "
        let output = builder.build(
            .mealSuggestion(existingMeals: [], freeDinnerSlots: []),
            preferences: prefs
        )
        XCTAssertFalse(output.contains("GUIDANCE"))
    }

    // MARK: - habitWeeklyAnalysis

    func testHabitAnalysisContainsHabitName() {
        let summary = HabitWeekSummary(name: "Gym", type: .good, weekTotal: 4, priorWeekTotal: 2)
        let output = builder.build(.habitWeeklyAnalysis(habits: [summary]), preferences: makePrefs())
        XCTAssertTrue(output.contains("HABITS_WEEK:"))
        XCTAssertTrue(output.contains("Gym=4"))
    }

    func testHabitAnalysisShowsUpTrend() {
        let summary = HabitWeekSummary(name: "Sleep", type: .good, weekTotal: 7, priorWeekTotal: 5)
        let output = builder.build(.habitWeeklyAnalysis(habits: [summary]), preferences: makePrefs())
        XCTAssertTrue(output.contains("↑"))
    }

    func testHabitAnalysisShowsDownTrend() {
        let summary = HabitWeekSummary(name: "Smoking", type: .bad, weekTotal: 2, priorWeekTotal: 5)
        let output = builder.build(.habitWeeklyAnalysis(habits: [summary]), preferences: makePrefs())
        XCTAssertTrue(output.contains("↓"))
    }

    func testHabitAnalysisShowsStableTrend() {
        let summary = HabitWeekSummary(name: "Reading", type: .good, weekTotal: 5, priorWeekTotal: 5)
        let output = builder.build(.habitWeeklyAnalysis(habits: [summary]), preferences: makePrefs())
        XCTAssertTrue(output.contains("→"))
    }

    func testHabitAnalysisMultipleHabitsJoinedByComma() {
        let s1 = HabitWeekSummary(name: "Gym",     type: .good, weekTotal: 4, priorWeekTotal: 3)
        let s2 = HabitWeekSummary(name: "Reading", type: .good, weekTotal: 6, priorWeekTotal: 6)
        let output = builder.build(.habitWeeklyAnalysis(habits: [s1, s2]), preferences: makePrefs())
        XCTAssertTrue(output.contains("Gym=4"))
        XCTAssertTrue(output.contains("Reading=6"))
    }
}
