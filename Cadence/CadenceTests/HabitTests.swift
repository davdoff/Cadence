import XCTest
import SwiftData
@testable import Cadence

final class HabitTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([Event.self, Cadence.Category.self, Meal.self, UserPreferences.self, Habit.self])
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

    func makeHabit(name: String = "Gym", type: HabitType = .good) -> Habit {
        let h = Habit(name: name, type: type)
        context.insert(h)
        return h
    }

    /// Returns the date N days from today (negative = past).
    func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    // MARK: - count / increment / decrement

    func testInitialCountIsZero() {
        let habit = makeHabit()
        XCTAssertEqual(habit.count(), 0)
    }

    func testIncrementAddsOne() {
        let habit = makeHabit()
        habit.increment()
        XCTAssertEqual(habit.count(), 1)
    }

    func testIncrementAddsTwice() {
        let habit = makeHabit()
        habit.increment()
        habit.increment()
        XCTAssertEqual(habit.count(), 2)
    }

    func testDecrementReducesCount() {
        let habit = makeHabit()
        habit.increment()
        habit.increment()
        habit.decrement()
        XCTAssertEqual(habit.count(), 1)
    }

    func testDecrementDoesNotGoBelowZero() {
        let habit = makeHabit()
        habit.decrement() // starts at 0
        XCTAssertEqual(habit.count(), 0)
    }

    func testCountForSpecificDateIsIndependent() {
        let habit = makeHabit()
        let yesterday = daysAgo(1)
        habit.increment(for: yesterday)
        habit.increment(for: yesterday)
        // Today's count should still be 0
        XCTAssertEqual(habit.count(), 0)
        XCTAssertEqual(habit.count(for: yesterday), 2)
    }

    func testCountUsesDateKey() {
        let habit = makeHabit()
        let today = Date()
        let key = Habit.key(for: today)
        habit.countLog[key] = 5
        XCTAssertEqual(habit.count(for: today), 5)
    }

    // MARK: - weeklyTotal

    func testWeeklyTotalIsZeroWithNoData() {
        let habit = makeHabit()
        XCTAssertEqual(habit.weeklyTotal(), 0)
    }

    func testWeeklyTotalSumsCurrentSevenDays() {
        let habit = makeHabit()
        // Set counts for 3 of the last 7 days
        for daysBack in [0, 2, 5] {
            let date = daysAgo(daysBack)
            habit.countLog[Habit.key(for: date)] = 2
        }
        // 3 days × 2 = 6
        XCTAssertEqual(habit.weeklyTotal(), 6)
    }

    func testWeeklyTotalExcludesDataOlderThan7Days() {
        let habit = makeHabit()
        // 8 days ago — should not be counted in the weekly total
        let oldDate = daysAgo(8)
        habit.countLog[Habit.key(for: oldDate)] = 10
        XCTAssertEqual(habit.weeklyTotal(), 0)
    }

    // MARK: - priorWeeklyTotal

    func testPriorWeeklyTotalSumsDays7Through13() {
        let habit = makeHabit()
        // Days 7 and 10 are in the prior week
        for daysBack in [7, 10] {
            let date = daysAgo(daysBack)
            habit.countLog[Habit.key(for: date)] = 3
        }
        XCTAssertEqual(habit.priorWeeklyTotal(), 6)
    }

    func testPriorWeeklyTotalIgnoresCurrentWeek() {
        let habit = makeHabit()
        habit.countLog[Habit.key(for: Date())] = 5  // today — should NOT appear in prior week
        XCTAssertEqual(habit.priorWeeklyTotal(), 0)
    }

    // MARK: - currentStreak

    func testCurrentStreakIsZeroWithNoData() {
        let habit = makeHabit()
        XCTAssertEqual(habit.currentStreak, 0)
    }

    func testCurrentStreakCountsConsecutiveDaysEndingToday() {
        let habit = makeHabit()
        // Set counts for today, yesterday, and 2 days ago
        for daysBack in 0..<3 {
            habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1
        }
        XCTAssertEqual(habit.currentStreak, 3)
    }

    func testCurrentStreakBrokenByGap() {
        let habit = makeHabit()
        // Today and 2 days ago — gap on day 1 breaks the streak
        habit.countLog[Habit.key(for: daysAgo(0))] = 1
        habit.countLog[Habit.key(for: daysAgo(2))] = 1
        XCTAssertEqual(habit.currentStreak, 1)
    }

    func testCurrentStreakSurvivesUnloggedToday() {
        let habit = makeHabit()
        // Three days through yesterday, today not logged yet — the run is still
        // locked in and only *at risk*.
        for daysBack in 1...3 {
            habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1
        }
        XCTAssertEqual(habit.currentStreak, 3)
        XCTAssertEqual(habit.streakState, .atRisk)
        XCTAssertFalse(habit.isLoggedToday)
    }

    func testLoggingTodayExtendsStreakAndMarksItSafe() {
        let habit = makeHabit()
        for daysBack in 1...3 {
            habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1
        }
        habit.increment()
        XCTAssertEqual(habit.currentStreak, 4)
        XCTAssertEqual(habit.streakState, .safe)
    }

    func testStreakStateIsNoneWithoutAStreak() {
        let habit = makeHabit()
        XCTAssertEqual(habit.streakState, .none)
    }

    func testCurrentStreakIsZeroWhenYesterdayAndTodayAreEmpty() {
        let habit = makeHabit()
        // Last log was two days ago — the run ended yesterday.
        habit.countLog[Habit.key(for: daysAgo(2))] = 1
        XCTAssertEqual(habit.currentStreak, 0)
        XCTAssertEqual(habit.streakState, .none)
    }

    // MARK: - Rest days

    func testRestDaysDoNotBreakTheStreak() {
        let habit = makeHabit()
        // Turn yesterday into a rest day and log the two days around it.
        let yesterdayWeekday = Calendar.current.component(.weekday, from: daysAgo(1))
        habit.activeDaysMask = Habit.allDaysMask & ~(1 << (yesterdayWeekday - 1))
        habit.countLog[Habit.key(for: daysAgo(0))] = 1
        habit.countLog[Habit.key(for: daysAgo(2))] = 1
        XCTAssertEqual(habit.currentStreak, 2)
    }

    func testStreakStateIsRestWhenTodayIsOffSchedule() {
        let habit = makeHabit()
        let todayWeekday = Calendar.current.component(.weekday, from: Date())
        habit.activeDaysMask = Habit.allDaysMask & ~(1 << (todayWeekday - 1))
        habit.countLog[Habit.key(for: daysAgo(1))] = 1
        XCTAssertEqual(habit.currentStreak, 1)
        XCTAssertEqual(habit.streakState, .rest)
    }

    func testEmptyActiveDaysMaskFallsBackToEveryDay() {
        let habit = makeHabit()
        habit.activeDaysMask = 0
        XCTAssertTrue(habit.isActiveDay(Date()))
        XCTAssertTrue(habit.isEveryDaySchedule)
    }

    func testNewHabitDefaultsToEveryDay() {
        let habit = makeHabit()
        XCTAssertEqual(habit.activeDaysMask, Habit.allDaysMask)
        XCTAssertEqual(habit.activeDays.count, 7)
    }

    // MARK: - bestStreak / milestones

    func testBestStreakIsZeroWithNoData() {
        let habit = makeHabit()
        XCTAssertEqual(habit.bestStreak, 0)
    }

    func testBestStreakFindsLongestHistoricalRun() {
        let habit = makeHabit()
        // 5-day run ten days back, 2-day run ending yesterday.
        for daysBack in 10...14 { habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1 }
        for daysBack in 1...2  { habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1 }
        XCTAssertEqual(habit.bestStreak, 5)
        XCTAssertEqual(habit.currentStreak, 2)
    }

    func testBestStreakNeverTrailsCurrentStreak() {
        let habit = makeHabit()
        for daysBack in 0...3 { habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1 }
        XCTAssertEqual(habit.bestStreak, habit.currentStreak)
    }

    func testMilestonesEarnedAtSevenDays() {
        let habit = makeHabit()
        for daysBack in 0...6 { habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1 }
        XCTAssertEqual(habit.currentStreak, 7)
        XCTAssertEqual(habit.earnedMilestones, [7])
    }

    func testNoMilestonesBelowSevenDays() {
        let habit = makeHabit()
        for daysBack in 0...2 { habit.countLog[Habit.key(for: daysAgo(daysBack))] = 1 }
        XCTAssertTrue(habit.earnedMilestones.isEmpty)
    }

    // MARK: - countHistory

    func testCountHistoryReturnsRequestedNumberOfDays() {
        let habit = makeHabit()
        let history = habit.countHistory(days: 7)
        XCTAssertEqual(history.count, 7)
    }

    func testCountHistoryIsOrderedOldestFirst() {
        let habit = makeHabit()
        let history = habit.countHistory(days: 7)
        for i in 0..<history.count - 1 {
            XCTAssertLessThan(history[i].date, history[i + 1].date)
        }
    }

    func testCountHistoryReflectsSetValues() {
        let habit = makeHabit()
        let yesterday = daysAgo(1)
        habit.countLog[Habit.key(for: yesterday)] = 4

        let history = habit.countHistory(days: 7)
        let yesterdayEntry = history.first { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        XCTAssertNotNil(yesterdayEntry)
        XCTAssertEqual(yesterdayEntry?.count, 4)
    }

    // MARK: - weekSummary

    func testWeekSummaryReflectsCurrentAndPriorWeek() {
        let habit = makeHabit()
        // Current week: 3 count
        habit.countLog[Habit.key(for: daysAgo(0))] = 3
        // Prior week: 5 count
        habit.countLog[Habit.key(for: daysAgo(7))] = 5

        let summary = habit.weekSummary()
        XCTAssertEqual(summary.name, "Gym")
        XCTAssertEqual(summary.type, .good)
        XCTAssertEqual(summary.weekTotal, 3)
        XCTAssertEqual(summary.priorWeekTotal, 5)
    }

    // MARK: - Initialisation defaults

    func testGoodHabitGetsDefaultGoodSymbol() {
        let habit = Habit(name: "Run", type: .good)
        XCTAssertEqual(habit.symbolName, "star.fill")
    }

    func testBadHabitGetsDefaultBadSymbol() {
        let habit = Habit(name: "Smoke", type: .bad)
        XCTAssertEqual(habit.symbolName, "bolt.slash.fill")
    }

    func testBadHabitDailyGoalIsAlwaysZero() {
        // Bad habits should not have a daily goal — the goal is always 0
        let habit = Habit(name: "Smoke", type: .bad, dailyGoal: 99)
        XCTAssertEqual(habit.dailyGoal, 0)
    }

    func testGoodHabitPreservesPositiveDailyGoal() {
        let habit = Habit(name: "Gym", type: .good, dailyGoal: 5)
        XCTAssertEqual(habit.dailyGoal, 5)
    }

    func testHabitNameIsPreserved() {
        let habit = makeHabit(name: "Meditation")
        XCTAssertEqual(habit.name, "Meditation")
    }

    // MARK: - Heatmap layout

    func testHeatmapCoversWholeMonthPlusLeadingPadding() {
        let habit = makeHabit()
        let cells = HabitHeatmapService.month(containing: Date()) { habit.count(for: $0) }
        let dayCount = Calendar.current.range(of: .day, in: .month, for: Date())!.count
        XCTAssertEqual(cells.filter { $0.date != nil }.count, dayCount)
        XCTAssertLessThan(cells.filter { $0.date == nil }.count, 7)
    }

    func testHeatmapReflectsCounts() {
        let habit = makeHabit()
        habit.countLog[Habit.key(for: Date())] = 3
        let cells = HabitHeatmapService.month(containing: Date()) { habit.count(for: $0) }
        let today = cells.first { $0.date.map { Calendar.current.isDateInToday($0) } == true }
        XCTAssertEqual(today?.count, 3)
    }

    func testHeatmapLevelScalesWithPeak() {
        XCTAssertEqual(HabitHeatmapService.level(count: 0, peak: 9), 0)
        XCTAssertEqual(HabitHeatmapService.level(count: 1, peak: 9), 1)
        XCTAssertEqual(HabitHeatmapService.level(count: 5, peak: 9), 2)
        XCTAssertEqual(HabitHeatmapService.level(count: 9, peak: 9), 3)
    }

    // MARK: - Goal celebration

    func testGoalCelebrationFiresOncePerDay() {
        let store = UserDefaults(suiteName: "HabitTests-\(UUID().uuidString)")!
        let id = UUID()
        XCTAssertTrue(HabitCelebrationTracker.claimCelebration(habitID: id, store: store))
        XCTAssertFalse(HabitCelebrationTracker.claimCelebration(habitID: id, store: store))
    }

    func testGoalCelebrationFiresAgainOnANewDay() {
        let store = UserDefaults(suiteName: "HabitTests-\(UUID().uuidString)")!
        let id = UUID()
        XCTAssertTrue(HabitCelebrationTracker.claimCelebration(habitID: id, on: daysAgo(1), store: store))
        XCTAssertTrue(HabitCelebrationTracker.claimCelebration(habitID: id, on: Date(), store: store))
    }

    func testGoalCelebrationIsPerHabit() {
        let store = UserDefaults(suiteName: "HabitTests-\(UUID().uuidString)")!
        XCTAssertTrue(HabitCelebrationTracker.claimCelebration(habitID: UUID(), store: store))
        XCTAssertTrue(HabitCelebrationTracker.claimCelebration(habitID: UUID(), store: store))
    }
}
