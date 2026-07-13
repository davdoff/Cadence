import XCTest
import SwiftData
@testable import Cadence

/// Covers the pure occurrence math (anchor + k·step, DST/month-length safety,
/// end-date cutoff) and the materialization rules: top-up is idempotent,
/// deleted occurrences never resurrect, "this and future" caps the series.
@MainActor
final class RecurrenceServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([Event.self, EventSeries.self, Cadence.Category.self, UserPreferences.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Fixed-zone helpers (pure math must not depend on the test machine)

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return cal
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func starts(_ rule: RecurrenceRule, anchor: Date, after: Date? = nil, until: Date) -> [Date] {
        RecurrenceService.occurrenceStarts(
            rule: rule, anchor: anchor, after: after ?? anchor, until: until, calendar: calendar
        )
    }

    // MARK: - Occurrence math

    func testDailyGeneratesEveryDayAfterAnchor() {
        let anchor = date(2030, 6, 1)
        let result = starts(RecurrenceRule(frequency: .daily, interval: 1, endDate: nil),
                            anchor: anchor, until: date(2030, 6, 5))
        XCTAssertEqual(result, [date(2030, 6, 2), date(2030, 6, 3), date(2030, 6, 4), date(2030, 6, 5)])
    }

    func testEveryThreeDaysUsesTheInterval() {
        let anchor = date(2030, 6, 1)
        let result = starts(RecurrenceRule(frequency: .daily, interval: 3, endDate: nil),
                            anchor: anchor, until: date(2030, 6, 10))
        XCTAssertEqual(result, [date(2030, 6, 4), date(2030, 6, 7), date(2030, 6, 10)])
    }

    func testWeeklyKeepsTheWeekday() {
        let anchor = date(2030, 6, 3) // a Monday
        let result = starts(RecurrenceRule(frequency: .weekly, interval: 2, endDate: nil),
                            anchor: anchor, until: date(2030, 7, 2))
        XCTAssertEqual(result, [date(2030, 6, 17), date(2030, 7, 1)])
    }

    func testMonthlyFromThe31stClampsButNeverDrifts() {
        // Jan 31 + 1 month clamps to Feb 28, but +2 months is computed from
        // the ANCHOR, so March lands back on the 31st — no cumulative drift.
        let anchor = date(2030, 1, 31)
        let result = starts(RecurrenceRule(frequency: .monthly, interval: 1, endDate: nil),
                            anchor: anchor, until: date(2030, 4, 30))
        XCTAssertEqual(result, [date(2030, 2, 28), date(2030, 3, 31), date(2030, 4, 30)])
    }

    func testYearly() {
        let anchor = date(2030, 8, 14)
        let result = starts(RecurrenceRule(frequency: .yearly, interval: 1, endDate: nil),
                            anchor: anchor, until: date(2032, 12, 31))
        XCTAssertEqual(result, [date(2031, 8, 14), date(2032, 8, 14)])
    }

    func testEndDateCutsTheSeries() {
        let anchor = date(2030, 6, 1)
        let result = starts(RecurrenceRule(frequency: .daily, interval: 1, endDate: date(2030, 6, 3, 23, 59)),
                            anchor: anchor, until: date(2030, 6, 30))
        XCTAssertEqual(result, [date(2030, 6, 2), date(2030, 6, 3)])
    }

    func testAfterBoundIsExclusiveUntilIsInclusive() {
        let anchor = date(2030, 6, 1)
        let result = starts(RecurrenceRule(frequency: .daily, interval: 1, endDate: nil),
                            anchor: anchor, after: date(2030, 6, 3), until: date(2030, 6, 5))
        // Jun 3 itself is excluded (already materialized); Jun 5 included.
        XCTAssertEqual(result, [date(2030, 6, 4), date(2030, 6, 5)])
    }

    func testDailyKeepsWallClockTimeAcrossDSTFallBack() {
        // Bucharest leaves DST on Oct 25 2026 — wall-clock 09:00 must survive.
        let anchor = date(2026, 10, 24)
        let result = starts(RecurrenceRule(frequency: .daily, interval: 1, endDate: nil),
                            anchor: anchor, until: date(2026, 10, 27))
        for start in result {
            XCTAssertEqual(calendar.component(.hour, from: start), 9)
        }
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - Materialization

    /// A daily series anchored just ahead of now, created through the same
    /// path AddEventView uses.
    private func makeDailySeries() -> Event {
        let anchor = Event(title: "Stretch",
                           startTime: Date.now.addingTimeInterval(3600),
                           endTime: Date.now.addingTimeInterval(3600 + 1800))
        context.insert(anchor)
        RecurrenceService.shared.createSeries(
            from: anchor,
            rule: RecurrenceRule(frequency: .daily, interval: 1, endDate: nil),
            context: context
        )
        return anchor
    }

    private func seriesEvents(_ seriesID: String?) -> [Event] {
        let all = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        return all.filter { $0.seriesID == seriesID }.sorted { $0.startTime < $1.startTime }
    }

    func testCreateSeriesMaterializesTheHorizon() {
        let anchor = makeDailySeries()
        XCTAssertNotNil(anchor.seriesID)
        let events = seriesEvents(anchor.seriesID)
        // Anchor + one per day up to ~90 days out.
        XCTAssertTrue((85...95).contains(events.count), "got \(events.count)")
        XCTAssertTrue(events.allSatisfy { $0.title == "Stretch" && $0.duration == 1800 })
    }

    func testTopUpIsIdempotent() {
        let anchor = makeDailySeries()
        let before = seriesEvents(anchor.seriesID).count
        RecurrenceService.shared.topUp(context: context)
        RecurrenceService.shared.topUp(context: context)
        XCTAssertEqual(seriesEvents(anchor.seriesID).count, before)
    }

    func testTopUpNeverResurrectsADeletedOccurrence() {
        let anchor = makeDailySeries()
        let victim = seriesEvents(anchor.seriesID)[5]
        let victimStart = victim.startTime
        context.delete(victim)

        RecurrenceService.shared.topUp(context: context)

        XCTAssertFalse(seriesEvents(anchor.seriesID).contains { $0.startTime == victimStart })
    }

    func testDeleteFutureKeepsThePastAndCapsTheSeries() {
        let anchor = makeDailySeries()
        let events = seriesEvents(anchor.seriesID)
        let cut = events[10]
        let cutStart = cut.startTime

        RecurrenceService.shared.deleteFuture(from: cut, context: context)

        let remaining = seriesEvents(anchor.seriesID)
        XCTAssertEqual(remaining.count, 10) // anchor + 9 before the cut
        XCTAssertTrue(remaining.allSatisfy { $0.startTime < cutStart })

        // The series is capped, so another top-up must not regrow the tail.
        RecurrenceService.shared.topUp(context: context)
        XCTAssertEqual(seriesEvents(anchor.seriesID).count, 10)
    }

    func testUpdateRuleRegeneratesOnlyTheFuture() {
        let anchor = makeDailySeries()
        let events = seriesEvents(anchor.seriesID)
        let pivot = events[10]

        RecurrenceService.shared.updateRule(
            from: pivot,
            to: RecurrenceRule(frequency: .weekly, interval: 1, endDate: nil),
            context: context
        )

        let after = seriesEvents(anchor.seriesID)
        let before = after.filter { $0.startTime < pivot.startTime }
        let regenerated = after.filter { $0.startTime > pivot.startTime }
        XCTAssertEqual(before.count, 10) // untouched daily history
        // Weekly over ~90 days ⇒ about 12 occurrences, all 7 days apart.
        XCTAssertTrue((10...14).contains(regenerated.count), "got \(regenerated.count)")
        let day: TimeInterval = 86_400
        for (a, b) in zip([pivot] + regenerated, regenerated) {
            let gap = b.startTime.timeIntervalSince(a.startTime)
            XCTAssertEqual(gap, 7 * day, accuracy: 2 * 3600) // ± DST shift
        }
    }

    func testEndSeriesStopsFutureMaterialization() {
        let anchor = makeDailySeries()
        RecurrenceService.shared.endSeries(from: anchor, context: context)

        let remaining = seriesEvents(anchor.seriesID)
        XCTAssertEqual(remaining.count, 1) // only the anchor survives

        RecurrenceService.shared.topUp(context: context)
        XCTAssertEqual(seriesEvents(anchor.seriesID).count, 1)
    }

    // MARK: - Series tombstone parsing (imported "delete this and future")

    func testSeriesTombstoneRoundTrip() {
        let cutoff = ISO8601DateFormatter().string(from: date(2030, 6, 10))
        let parsed = CalendarImportService.seriesTombstones(in: [
            "plain-occurrence@test",                    // per-occurrence entry: ignored
            "series:uid@host@" + cutoff,                // id itself contains '@'
            "series:broken-no-date",                    // malformed: skipped
        ])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed["uid@host"], date(2030, 6, 10))
    }
}
