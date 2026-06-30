import XCTest
import SwiftData
@testable import Cadence

final class MealSchedulerServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    let service = MealSchedulerService()

    override func setUp() {
        super.setUp()
        let schema = Schema([Event.self, Category.self, Meal.self, UserPreferences.self])
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

    func makeMeal(name: String = "Pasta", prep: Int = 30) -> Meal {
        let m = Meal(name: name, prepTimeMinutes: prep)
        context.insert(m)
        return m
    }

    /// Date for `daysFromNow` at the given hour:minute (local time).
    func at(_ hour: Int, _ minute: Int = 0, daysFromNow: Int = 0) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour; comps.minute = minute; comps.second = 0
        var d = Calendar.current.date(from: comps)!
        if daysFromNow != 0 {
            d = Calendar.current.date(byAdding: .day, value: daysFromNow, to: d)!
        }
        return d
    }

    func makeEvent(title: String = "Test", start: Date, end: Date, status: EventStatus = .pending, source: EventSource = .manual) -> Event {
        let e = Event(title: title, startTime: start, endTime: end, source: source)
        e.status = status
        context.insert(e)
        return e
    }

    func next7Days() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    // MARK: - Breakfast: basic scheduling

    func testBreakfastScheduledOnFreeDay() {
        let prefs = makePrefs()
        prefs.breakfastEnabled = true
        prefs.breakfastHour = 8
        prefs.breakfastMinute = 0
        prefs.breakfastDuration = 30

        let targetDate = Calendar.current.startOfDay(for: at(0, daysFromNow: 1))
        let result = service.scheduleBreakfastIfNeeded(
            existingEvents: [],
            preferences: prefs,
            targetDates: [targetDate]
        )

        XCTAssertEqual(result.count, 1)
        let event = result[0]
        XCTAssertEqual(event.title, "Breakfast")
        XCTAssertEqual(event.source, .ai)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: event.startTime)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(event.endTime.timeIntervalSince(event.startTime), 30 * 60, accuracy: 1)
    }

    func testBreakfastSkippedWhenDisabled() {
        let prefs = makePrefs()
        prefs.breakfastEnabled = false
        let dates = next7Days()
        let result = service.scheduleBreakfastIfNeeded(existingEvents: [], preferences: prefs, targetDates: dates)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Breakfast: skip-day logic when conflict exists

    func testBreakfastSkippedWhenConflictWithin30Min() {
        let prefs = makePrefs()
        prefs.breakfastEnabled = true
        prefs.breakfastHour = 8
        prefs.breakfastMinute = 0
        prefs.breakfastDuration = 30

        let targetDate = Calendar.current.startOfDay(for: Date())
        // Event starts 20 min before breakfast → within 30-min window
        let conflictStart = at(7, 40)
        let conflictEnd   = at(8, 10)
        let conflict = makeEvent(start: conflictStart, end: conflictEnd)

        let result = service.scheduleBreakfastIfNeeded(
            existingEvents: [conflict],
            preferences: prefs,
            targetDates: [targetDate]
        )
        XCTAssertTrue(result.isEmpty, "Breakfast should be skipped when conflict within 30 min")
    }

    func testBreakfastNotSkippedWhenConflictBeyond30Min() {
        let prefs = makePrefs()
        prefs.breakfastEnabled = true
        prefs.breakfastHour = 8
        prefs.breakfastMinute = 0
        prefs.breakfastDuration = 30

        let targetDate = Calendar.current.startOfDay(for: Date())
        // Event ends 40 min before breakfast → outside 30-min window
        let conflictStart = at(7, 0)
        let conflictEnd   = at(7, 20)
        let conflict = makeEvent(start: conflictStart, end: conflictEnd)

        let result = service.scheduleBreakfastIfNeeded(
            existingEvents: [conflict],
            preferences: prefs,
            targetDates: [targetDate]
        )
        XCTAssertEqual(result.count, 1, "Breakfast should be scheduled when conflict is >30 min away")
    }

    func testBreakfastSkippedWhenAlreadyScheduledThatDay() {
        let prefs = makePrefs()
        prefs.breakfastEnabled = true
        prefs.breakfastHour = 8
        prefs.breakfastMinute = 0
        prefs.breakfastDuration = 30

        let targetDate = Calendar.current.startOfDay(for: Date())
        let existing = makeEvent(title: "Breakfast", start: at(8), end: at(8, 30), source: .ai)

        let result = service.scheduleBreakfastIfNeeded(
            existingEvents: [existing],
            preferences: prefs,
            targetDates: [targetDate]
        )
        XCTAssertTrue(result.isEmpty, "Breakfast should not be duplicated")
    }

    func testBreakfastMissedEventDoesNotCountAsConflict() {
        let prefs = makePrefs()
        prefs.breakfastEnabled = true
        prefs.breakfastHour = 8
        prefs.breakfastMinute = 0

        let targetDate = Calendar.current.startOfDay(for: Date())
        let missed = makeEvent(start: at(7, 50), end: at(8, 20), status: .missed)

        let result = service.scheduleBreakfastIfNeeded(
            existingEvents: [missed],
            preferences: prefs,
            targetDates: [targetDate]
        )
        XCTAssertEqual(result.count, 1, "Missed events should not block breakfast scheduling")
    }

    func testBreakfastDurationCappedAt30Min() throws {
        let prefs = makePrefs()
        prefs.breakfastEnabled = true
        prefs.breakfastHour = 8
        prefs.breakfastDuration = 60 // set to 60 — should be capped at 30

        let targetDate = Calendar.current.startOfDay(for: Date())
        let result = service.scheduleBreakfastIfNeeded(existingEvents: [], preferences: prefs, targetDates: [targetDate])

        let event = try XCTUnwrap(result.first, "Expected a breakfast event to be created")
        XCTAssertEqual(event.endTime.timeIntervalSince(event.startTime), 30 * 60, accuracy: 1)
    }

    // MARK: - Dinner: free slot selection

    func testDinnerScheduledInFreeWindow() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowStartMinute = 0
        prefs.dinnerWindowEndHour = 22
        prefs.dinnerWindowEndMinute = 0

        let meal = makeMeal(name: "Stir Fry", prep: 30)
        let dates = [Calendar.current.startOfDay(for: Date())]

        let result = service.scheduleDinnerSlots(
            existingEvents: [],
            meals: [meal],
            preferences: prefs,
            targetDates: dates
        )

        XCTAssertEqual(result.count, 1)
        let event = result[0]
        XCTAssertEqual(event.title, "Stir Fry")
        XCTAssertEqual(event.source, .ai)

        let startComps = Calendar.current.dateComponents([.hour, .minute], from: event.startTime)
        XCTAssertGreaterThanOrEqual(startComps.hour!, 19)
        XCTAssertLessThan(startComps.hour!, 22)
    }

    func testDinnerSkippedWhenWindowFull() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowEndHour = 22
        prefs.bufferMinutes = 0

        // Fill the entire dinner window
        let block = makeEvent(start: at(19), end: at(22), source: .ai)
        let meal = makeMeal()
        let dates = [Calendar.current.startOfDay(for: Date())]

        let result = service.scheduleDinnerSlots(
            existingEvents: [block],
            meals: [meal],
            preferences: prefs,
            targetDates: dates
        )
        XCTAssertTrue(result.isEmpty, "Dinner should be skipped when no free slot exists")
    }

    func testDinnerSkippedWhenNoPrepTimeFits() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowEndHour = 22
        prefs.bufferMinutes = 0

        // Only 20 min free in window (19:00–19:20), meal takes 60 min
        let block = makeEvent(start: at(19, 20), end: at(22), source: .manual)
        let meal = makeMeal(prep: 60)
        let dates = [Calendar.current.startOfDay(for: Date())]

        let result = service.scheduleDinnerSlots(
            existingEvents: [block],
            meals: [meal],
            preferences: prefs,
            targetDates: dates
        )
        XCTAssertTrue(result.isEmpty, "Dinner should be skipped when prep time doesn't fit in remaining slot")
    }

    func testDinnerNotDoubleBookedAcrossWeek() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowEndHour = 22
        prefs.bufferMinutes = 0

        let meal = makeMeal(prep: 30)
        let dates = (0..<3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }

        let result = service.scheduleDinnerSlots(
            existingEvents: [],
            meals: [meal],
            preferences: prefs,
            targetDates: dates
        )

        // One event per day — no two events on the same day
        let groupedByDay = Dictionary(grouping: result) {
            Calendar.current.startOfDay(for: $0.startTime)
        }
        for (_, events) in groupedByDay {
            XCTAssertEqual(events.count, 1, "At most one dinner event per day")
        }
    }

    func testDinnerEmptyMealListProducesNoEvents() {
        let prefs = makePrefs()
        let result = service.scheduleDinnerSlots(
            existingEvents: [],
            meals: [],
            preferences: prefs,
            targetDates: next7Days()
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Breakfast missed-3-days streak detection

    func testStreakZeroWhenNoBreakfastEvents() {
        let count = service.breakfastMissedStreakCount(events: [])
        XCTAssertEqual(count, 0)
    }

    func testStreakCountsConsecutiveMissedDays() {
        // Create 3 consecutive missed breakfast events ending today
        var events: [Event] = []
        for daysAgo in 0..<3 {
            let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date()))!
            let start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
            let end = start.addingTimeInterval(30 * 60)
            let e = makeEvent(title: "Breakfast", start: start, end: end, status: .missed, source: .ai)
            events.append(e)
        }
        let count = service.breakfastMissedStreakCount(events: events)
        XCTAssertEqual(count, 3)
    }

    func testStreakBrokenByCompletedDay() {
        // 2 missed, then 1 completed earlier → streak should be 2
        var events: [Event] = []
        for daysAgo in 0..<3 {
            let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date()))!
            let start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
            let end = start.addingTimeInterval(30 * 60)
            let status: EventStatus = daysAgo < 2 ? .missed : .completed
            let e = makeEvent(title: "Breakfast", start: start, end: end, status: status, source: .ai)
            events.append(e)
        }
        let count = service.breakfastMissedStreakCount(events: events)
        XCTAssertEqual(count, 2)
    }

    func testStreakZeroWhenMostRecentBreakfastCompleted() {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: today)!
        let e = makeEvent(title: "Breakfast", start: start, end: start.addingTimeInterval(30 * 60), status: .completed, source: .ai)
        let count = service.breakfastMissedStreakCount(events: [e])
        XCTAssertEqual(count, 0)
    }

    // MARK: - remainingDinnerSlots

    func testRemainingDinnerSlotsReturnsFullWindowWhenNoEvents() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowEndHour = 22
        prefs.bufferMinutes = 0

        let dates = [Calendar.current.startOfDay(for: Date())]
        let slots = service.remainingDinnerSlots(
            for: dates,
            existingEvents: [],
            scheduledDinnerEvents: [],
            preferences: prefs,
            minimumMinutes: 30
        )

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].duration, 3 * 3600, accuracy: 1) // 19:00–22:00 = 3 hours
    }

    func testRemainingDinnerSlotsIsEmptyWhenWindowFull() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowEndHour = 22
        prefs.bufferMinutes = 0

        let block = makeEvent(start: at(19), end: at(22))
        let dates = [Calendar.current.startOfDay(for: Date())]

        let slots = service.remainingDinnerSlots(
            for: dates,
            existingEvents: [block],
            scheduledDinnerEvents: [],
            preferences: prefs,
            minimumMinutes: 30
        )
        XCTAssertTrue(slots.isEmpty)
    }

    func testRemainingDinnerSlotsAccountsForScheduledDinnerEvents() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowEndHour = 22
        prefs.bufferMinutes = 0

        // A dinner event already fills 19:00–20:30
        let scheduled = makeEvent(start: at(19), end: at(20, 30), source: .ai)
        let dates = [Calendar.current.startOfDay(for: Date())]

        let slots = service.remainingDinnerSlots(
            for: dates,
            existingEvents: [],
            scheduledDinnerEvents: [scheduled],
            preferences: prefs,
            minimumMinutes: 30 // 20:30–22:00 = 90 min → should find a slot
        )
        XCTAssertFalse(slots.isEmpty)
    }

    func testRemainingDinnerSlotsMissedEventDoesNotBlock() {
        let prefs = makePrefs()
        prefs.dinnerWindowStartHour = 19
        prefs.dinnerWindowEndHour = 22
        prefs.bufferMinutes = 0

        let missed = makeEvent(start: at(19), end: at(22), status: .missed)
        let dates = [Calendar.current.startOfDay(for: Date())]

        let slots = service.remainingDinnerSlots(
            for: dates,
            existingEvents: [missed],
            scheduledDinnerEvents: [],
            preferences: prefs,
            minimumMinutes: 30
        )
        // Missed events don't block the window
        XCTAssertFalse(slots.isEmpty)
    }

    // MARK: - nearestUpcomingMeal

    func testNearestUpcomingMealReturnsNilForEmptyList() {
        XCTAssertNil(service.nearestUpcomingMeal(from: []))
    }

    func testNearestUpcomingMealReturnsSoonestPendingFutureEvent() {
        let sooner = makeEvent(title: "Breakfast", start: at(8, daysFromNow: 1), end: at(8, 30, daysFromNow: 1))
        let later  = makeEvent(title: "Dinner",    start: at(19, daysFromNow: 1), end: at(20, daysFromNow: 1))

        let result = service.nearestUpcomingMeal(from: [later, sooner])
        XCTAssertEqual(result?.title, "Breakfast")
    }

    func testNearestUpcomingMealIgnoresPastEvents() {
        let past = makeEvent(title: "Breakfast", start: at(8, daysFromNow: -1), end: at(8, 30, daysFromNow: -1))
        XCTAssertNil(service.nearestUpcomingMeal(from: [past]))
    }

    func testNearestUpcomingMealIgnoresMissedFutureEvents() {
        let missed = makeEvent(title: "Dinner", start: at(19, daysFromNow: 1), end: at(20, daysFromNow: 1), status: .missed)
        XCTAssertNil(service.nearestUpcomingMeal(from: [missed]))
    }

    func testNearestUpcomingMealReturnsNilWhenAllEventsAreCompleted() {
        let done = makeEvent(title: "Breakfast", start: at(8, daysFromNow: 1), end: at(8, 30, daysFromNow: 1), status: .completed)
        XCTAssertNil(service.nearestUpcomingMeal(from: [done]))
    }
}
