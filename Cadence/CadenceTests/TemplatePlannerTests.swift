import XCTest
import SwiftData
@testable import Cadence

final class TemplatePlannerTests: XCTestCase {

    let cal = Calendar.current
    /// A fixed Monday, so tests never depend on today's date.
    lazy var day: Date = cal.date(from: DateComponents(year: 2026, month: 7, day: 6))!

    // MARK: - Helpers

    func t(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let base = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: day))!
        return base.addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
    }

    func block(_ title: String, _ hour: Int, _ minute: Int = 0, minutes: Int = 60) -> TemplateBlock {
        TemplateBlock(title: title, startMinuteOfDay: hour * 60 + minute, durationMinutes: minutes, categoryName: "Work")
    }

    func existing(_ title: String, _ start: Date, _ end: Date) -> TemplatePlanner.ExistingItem {
        TemplatePlanner.ExistingItem(id: UUID(), title: title, start: start, end: end)
    }

    // MARK: - Placement

    func testEmptyDayKeepsTemplateTimesAndBackToBackBlocks() {
        let plan = TemplatePlanner.plan(
            template: [block("A", 9), block("B", 10)], on: day, existing: [], bufferMinutes: 15
        )
        XCTAssertEqual(plan.blocks.map(\.outcome), [.asIs, .asIs])
        // No buffer between two template blocks — back-to-back is intentional.
        XCTAssertEqual(plan.blocks[0].start, t(9))
        XCTAssertEqual(plan.blocks[1].start, t(10))
        XCTAssertTrue(plan.moves.isEmpty)
    }

    func testClashShiftsToNearestGapRespectingBuffer() {
        let dentist = existing("Dentist", t(9), t(10))
        let plan = TemplatePlanner.plan(
            template: [block("Deep work", 9)], on: day, existing: [dentist], bufferMinutes: 15
        )
        let placed = plan.blocks[0]
        // 7:45 and 10:15 are equally near; the later one wins.
        XCTAssertEqual(placed.outcome, .shifted(from: t(9)))
        XCTAssertEqual(placed.start, t(10, 15))
        XCTAssertEqual(placed.end, t(11, 15))
        XCTAssertEqual(placed.clashesWith, [dentist.id])
    }

    func testShiftedBlocksKeepTheirOrder() {
        let call = existing("Call", t(9), t(9, 30))
        let plan = TemplatePlanner.plan(
            template: [block("A", 9), block("B", 10)], on: day, existing: [call], bufferMinutes: 0
        )
        XCTAssertEqual(plan.blocks[0].start, t(9, 30))
        XCTAssertEqual(plan.blocks[1].start, t(10, 30))
        XCTAssertLessThan(plan.blocks[0].start, plan.blocks[1].start)
    }

    func testMoveExistingKeepsBlockTimeAndMovesTheEvent() {
        let dentist = existing("Dentist", t(9), t(10))
        let plan = TemplatePlanner.plan(
            template: [block("Deep work", 9)], on: day, existing: [dentist],
            moveExisting: [dentist.id], bufferMinutes: 0
        )
        XCTAssertEqual(plan.blocks[0].outcome, .asIs)
        XCTAssertEqual(plan.blocks[0].start, t(9))
        // Still reported as a clash, so the UI keeps showing its toggle.
        XCTAssertEqual(plan.blocks[0].clashesWith, [dentist.id])
        XCTAssertEqual(plan.moves, [TemplatePlanner.ExistingMove(eventID: dentist.id, newStart: t(10), newEnd: t(11))])
    }

    func testFullDayMakesBlockUnplaceable() {
        let allDay = existing("Trip", t(0), t(0, dayOffset: 1))
        let plan = TemplatePlanner.plan(
            template: [block("Gym", 18)], on: day, existing: [allDay], bufferMinutes: 0
        )
        XCTAssertEqual(plan.blocks[0].outcome, .unplaceable)
        XCTAssertTrue(plan.placedBlocks.isEmpty)
    }

    func testEventWithNowhereToGoStaysAndIsReported() {
        let dentist = existing("Dentist", t(9), t(10))
        let wholeDay = block("Retreat", 0, minutes: 24 * 60)
        let plan = TemplatePlanner.plan(
            template: [wholeDay], on: day, existing: [dentist],
            moveExisting: [dentist.id], bufferMinutes: 0
        )
        XCTAssertEqual(plan.unmovable, [dentist.id])
        XCTAssertTrue(plan.moves.isEmpty)
        // Re-planned with the dentist fixed, the whole-day block can't fit.
        XCTAssertEqual(plan.blocks[0].outcome, .unplaceable)
    }

    func testNotBeforePushesBlocksPastNow() {
        let plan = TemplatePlanner.plan(
            template: [block("Morning run", 8)], on: day, existing: [], bufferMinutes: 0, notBefore: t(10)
        )
        XCTAssertEqual(plan.blocks[0].outcome, .shifted(from: t(8)))
        XCTAssertEqual(plan.blocks[0].start, t(10))
    }

    func testPlanPeriodPlansEachDayAgainstItsOwnEvents() {
        let tuesdayMeeting = existing("Meeting", t(9, dayOffset: 1), t(10, dayOffset: 1))
        let plans = TemplatePlanner.planPeriod(
            assignments: [
                (day: t(0, dayOffset: 1), blocks: [block("Focus", 9)]),
                (day: t(0), blocks: [block("Focus", 9)]),
            ],
            existing: [tuesdayMeeting],
            bufferMinutes: 0
        )
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].day, t(0))                  // sorted by date
        XCTAssertEqual(plans[0].blocks[0].outcome, .asIs)
        XCTAssertEqual(plans[1].blocks[0].outcome, .shifted(from: t(9, dayOffset: 1)))
    }

    // MARK: - From SwiftData events

    func testMissedAndDisplacedEventsDoNotBlock() throws {
        let schema = Schema([Event.self, Cadence.Category.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let missed = Event(title: "Missed", startTime: t(9), endTime: t(10))
        missed.status = .missed
        let displaced = Event(title: "Displaced", startTime: t(9), endTime: t(10))
        displaced.status = .displaced
        let kept = Event(title: "Kept", startTime: t(14), endTime: t(15))
        for event in [missed, displaced, kept] { context.insert(event) }

        let items = TemplatePlanner.existingItems(from: [missed, displaced, kept])
        XCTAssertEqual(items.map(\.title), ["Kept"])
    }

    func testCopyingADayTurnsEventsIntoBlocks() throws {
        let schema = Schema([Event.self, Cadence.Category.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let gym = Event(title: "Gym", startTime: t(18, 30), endTime: t(19, 45))
        let missed = Event(title: "Skipped", startTime: t(8), endTime: t(9))
        missed.status = .missed
        let otherDay = Event(title: "Tomorrow", startTime: t(9, dayOffset: 1), endTime: t(10, dayOffset: 1))
        for event in [gym, missed, otherDay] { context.insert(event) }

        let blocks = DayTemplateEditorView.blocks(copying: day, from: [gym, missed, otherDay], calendar: cal)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].title, "Gym")
        XCTAssertEqual(blocks[0].startMinuteOfDay, 18 * 60 + 30)
        XCTAssertEqual(blocks[0].durationMinutes, 75)
    }
}
